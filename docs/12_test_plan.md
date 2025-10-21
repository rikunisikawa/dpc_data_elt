# DPC 学習基盤 テスト計画（E2E / 回帰）

## 目的
学習環境でのデータ処理の信頼性を担保するため、E2E テストおよび回帰テストの範囲、手順、評価指標を定義する。

## テスト方針
- **E2E テスト**: S3 raw ファイル投入から mart 生成、DQ、QuickSight 更新までを自動確認。
- **回帰テスト**: dbt テストと pytest を併用し、既存の KPI が変化していないことを検証。
- ゴールデンデータ（少量のサンプル DPC データ）を GitHub リポジトリの `tests/data` に配置。

## テスト観点表
| ID | 種別 | 観点 | 成功基準 |
| --- | --- | --- | --- |
| E2E-01 | E2E | S3 raw → COPY → stage → mart の処理完了 | Step Functions 実行が SUCCESS、全 Lambda が成功 |
| E2E-02 | E2E | DQ 結果の重大なし | `dq.results_yyyymm` に重大ルールが 0 件 |
| E2E-03 | E2E | QuickSight データセット更新 | API レスポンスが 200、SPICE 更新完了 |
| REG-01 | 回帰 | 件数検証 | `fact_case_summary` 件数 = ゴールデン比 |
| REG-02 | 回帰 | 合計点数 | `fact_cost_monthly.total_points` = 期待値 |
| REG-03 | 回帰 | KPI | LOS / 再入院率が許容誤差 ±0.1% 以内 |

## E2E シナリオ手順
1. ゴールデンデータを `s3://dpc-learning-data-dev/raw/yyyymm=2025-04/` にアップロード。
2. `_manifest.json` を更新し、`records`, `hash` を記載。
3. Step Functions ステートマシン `dpc-learning-elt` を `StartExecution`（入力 `{ "yyyymm": "202504" }`）で起動。
4. 実行完了後、以下を検証:
   - CloudWatch Logs: 例外なし。
   - Redshift: `SELECT COUNT(*) FROM mart.fact_case_summary WHERE yyyymm='202504';`
   - DQ: `SELECT * FROM dq.results_yyyymm WHERE severity='CRITICAL' AND yyyymm='202504';`
   - S3 processed: Parquet 出力が存在。
5. QuickSight API `UpdateDataSet` を呼び出し SPICE 更新。
6. Slack 通知メッセージを確認。

## 回帰テスト構成
### dbt tests
- コマンド: `dbt test --select state:modified`
- 追加: `dbt test --select mart.fact_case_summary`（LOS 計算用カスタムテスト）

### pytest 雛形
`tests/test_metrics.py`
```python
import json
from decimal import Decimal

import boto3

EXPECTED = {
    "fact_case_summary_count": 1250,
    "fact_cost_monthly_total_points": Decimal("3456789"),
    "los_avg": Decimal("12.4"),
    "readmit_30d_rate": Decimal("0.045")
}

redshift = boto3.client("redshift-data")


def fetch_scalar(sql: str) -> Decimal:
    resp = redshift.execute_statement(
        ClusterIdentifier="dpc-learning-dev",
        Database="dpc",
        Sql=sql
    )
    result = redshift.get_statement_result(Id=resp["Id"]) 
    return Decimal(result["Records"][0][0]["stringValue"])


def test_fact_case_summary_count():
    value = fetch_scalar("SELECT COUNT(*) FROM mart.fact_case_summary WHERE yyyymm='202504'")
    assert value == EXPECTED["fact_case_summary_count"]


def test_total_points():
    value = fetch_scalar("SELECT SUM(total_points) FROM mart.fact_cost_monthly WHERE year_month='202504'")
    assert value == EXPECTED["fact_cost_monthly_total_points"]


def test_los_average():
    value = fetch_scalar("SELECT ROUND(AVG(length_of_stay), 1) FROM mart.fact_case_summary WHERE yyyymm='202504'")
    assert abs(value - EXPECTED["los_avg"]) <= Decimal("0.1")


def test_readmit_rate():
    value = fetch_scalar("SELECT ROUND(AVG(readmit_30d_flag::int), 3) FROM mart.fact_case_summary WHERE yyyymm='202504'")
    assert abs(value - EXPECTED["readmit_30d_rate"]) <= Decimal("0.001")
```

### テストデータ管理
- ゴールデンデータを更新する際は `EXPECTED` 値を同時更新。
- 大量データのテストは `pytest -m heavy` でマークし、スケジュール実行でのみ実施。

## コマンド一覧
| フェーズ | コマンド |
| --- | --- |
| E2E | `aws stepfunctions start-execution --state-machine-arn <arn> --input '{"yyyymm":"202504"}'`
| 回帰 | `dbt test --select state:modified` |
| 回帰 | `pytest tests/test_metrics.py` |

## 判定基準
- 全テストケース成功。
- 設定した許容誤差を超える差分が発生した場合は障害扱い。
- E2E テストが失敗した場合は、再度 Step Functions を手動実行し原因を特定。

## 決定事項 / 未決事項
- **決定事項**
  - E2E テストは Step Functions 実行をトリガーとし、Slack 通知まで検証する。
  - 回帰テストは dbt tests + pytest の 2 段構成で実施し、ゴールデンデータとの差分をチェックする。
  - 許容誤差は LOS ±0.1 日、再入院率 ±0.1% を基準とする。
- **未決事項**
  - QuickSight SPICE 更新を自動で検証する API 呼出権限の実装が未確定。
  - pytest をどのタイミングで実行するか（CI か定期バッチか）の最終決定が必要。
  - ゴールデンデータ更新手順（承認フロー）の整備が未完。
