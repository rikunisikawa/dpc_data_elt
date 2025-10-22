# タスク 06: データ品質チェックの最小構成

## 目的
docs/08_data_quality.md を基に、学習環境で実装負荷の低い DQ チェックを整備します。将来の高度な監視は scope 外です。

## 前提条件
- dbt プロジェクトが初期化済み（タスク04）。
- Redshift に raw/stage/mart テーブルが存在する。

## 手順
1. **dbt tests の整理**
   - 既存モデルの `unique`, `not_null` テストを `models/**/schema.yml` に定義します。
   - 追加で簡易的な `accepted_values` テスト（例: 性別コードなど）を導入します。
   - 各テストに `meta.dq_rule_id`, `meta.dq_severity`, `meta.dq_note`, `meta.dq_facility_column`, `meta.dq_sample_key_columns` を設定し、後続の自動登録に必要な情報を付与します。
2. **Lambda からの DQ 実行**
   - タスク03で作成した `dpc-dbt-tests` (ECS 実行) を利用し、`dbt test --store-failures` を実行します。
   - `tools/run_dbt_dq.py` をコンテナ内で実行し、`target/run_results.json` と `target/manifest.json` から失敗テストを解析して `dq.results_yyyymm` に登録します。
   - Secrets Manager から取得した資格情報で Redshift Data API に接続し、対象年月・施設の既存レコードを削除してから INSERT します。
3. **エスカレーション設定**
   - docs/08_data_quality.md の `ref.dim_service_code` 更新頻度未定項目は、当面 Slack 通知のみとし、エスカレーション先は学習者自身に設定します。
   - `ZERO_COST_CASE` の許容割合検証は後回しにし、将来の TODO として記録します。

## 完了条件
- dbt test 実行結果が Redshift に記録される。
- DQ 失敗時に Slack 通知を受け取れる。
- 未実装の高度な指標が README などに TODO として記載されている。
