# DPC 学習基盤 S3 データ配置・命名規約

## 目的
DPC ファイルを学習用 S3 バケットに一貫して配置するための命名規約とメタデータ管理ルールを定義する。

## バケット構造
- **バケット名**: `dpc-learning-data-<env>` （例: `dpc-learning-data-dev`）。
- **トップレベル構造**:
  - `raw/` – 提出ファイルの原本保管。年月パーティションで管理。
  - `stage/` – 加工中間ファイル（オプション）。
  - `processed/` – mart からのエクスポート成果（CSV/Parquet）。
  - `archive/` – raw から移動した長期保管データ。
  - `logs/` – Step Functions, DQ 結果など付随ログ。

```text
s3://dpc-learning-data-<env>/
  ├── raw/
  │    └── yyyymm=YYYY-MM/
  │         ├── y1/
  │         │    └── {facility}_{yyyymm}_y1_{seq}.csv
  │         ├── y3/
  │         │    └── ...
  │         ├── y4/
  │         ├── ef_in/
  │         ├── ef_out/
  │         ├── d/
  │         ├── h/
  │         └── k/
  │              └── _manifest.json
  ├── stage/
  ├── processed/
  ├── archive/
  └── logs/
```

## 命名規約
| 項目 | 規則 |
| --- | --- |
| ルート | `s3://dpc-learning-data-<env>/` |
| 年月パーティション | `raw/yyyymm=<YYYY-MM>/` （ゼロ埋め、例: `raw/yyyymm=2025-04/`） |
| file_type | `y1`, `y3`, `y4`, `ef_in`, `ef_out`, `d`, `h`, `k` |
| ファイル名 | `{facility_cd}_{yyyymm}_{file_type}_{seq}.{ext}` |
| facility_cd | 9桁。例: `131000123` |
| yyyymm | `YYYYMM` 表記。例: `202504` |
| seq | 3桁連番。例: `001` |
| ext | 原本形式に準じる（CSV, TXT, dat 等）。 |

### 命名例
| ファイル種別 | パス例 |
| --- | --- |
| 様式1 (退院患者票) | `s3://dpc-learning-data-dev/raw/yyyymm=2025-04/y1/131000123_202504_y1_001.csv` |
| 様式3 (施設票) | `s3://dpc-learning-data-dev/raw/yyyymm=2025-04/y3/131000123_202504_y3_001.csv` |
| EF 入院 | `s3://dpc-learning-data-dev/raw/yyyymm=2025-04/ef_in/131000123_202504_ef_in_001.csv` |
| K (共通ID) | `s3://dpc-learning-data-dev/raw/yyyymm=2025-04/k/131000123_202504_k_001.csv` |

## 監査マニフェスト `_manifest.json`
- 各 `raw/yyyymm=.../<file_type>/` フォルダに一つ配置。
- 取込バッチ開始時に Lambda が検証。

### JSON スキーマ
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "DPC Raw Manifest",
  "type": "object",
  "required": ["yyyymm", "file_type", "facility_cd", "records", "hash", "created_at"],
  "properties": {
    "yyyymm": {
      "type": "string",
      "pattern": "^\\d{6}$"
    },
    "file_type": {
      "type": "string",
      "enum": ["y1", "y3", "y4", "ef_in", "ef_out", "d", "h", "k"]
    },
    "facility_cd": {
      "type": "string",
      "pattern": "^\\d{9}$"
    },
    "records": {
      "type": "integer",
      "minimum": 0
    },
    "hash": {
      "type": "object",
      "required": ["algorithm", "value"],
      "properties": {
        "algorithm": {
          "type": "string",
          "enum": ["MD5", "SHA256"]
        },
        "value": {
          "type": "string",
          "pattern": "^[A-Fa-f0-9]{32,64}$"
        }
      }
    },
    "created_at": {
      "type": "string",
      "format": "date-time"
    },
    "notes": {
      "type": "string"
    }
  }
}
```

### サンプル
```json
{
  "yyyymm": "202504",
  "file_type": "y1",
  "facility_cd": "131000123",
  "records": 1250,
  "hash": {
    "algorithm": "SHA256",
    "value": "ab45c1d4fef2d9b6a7d4e8c91bb2302c1f4b9cd271b1d6a5f8c1234567890abc"
  },
  "created_at": "2025-05-01T03:45:00+09:00",
  "notes": "1Q診療分"
}
```

## ライフサイクルポリシー
| 対象パス | ルール |
| --- | --- |
| `raw/yyyymm=*` | 13 か月保管後に `archive/yyyymm=...` へ移動。 |
| `archive/` | 5 年保持後に Glacier Deep Archive へ移行。 |
| `_manifest.json` | raw と同じスケジュールで archive へ移動。 |
| `logs/` | 180 日後に削除。 |

Lifecycle ポリシーは S3 バケット設定で構成し、移動後もプレフィックス構造を維持する。

## 運用ルール
- 提出完了時に `_manifest.json` を必ず更新。複数ファイルがある場合、`records` / `hash` を配列化せずファイル毎にマニフェストを作成。
- Lambda `validate_manifest` で以下を確認：
  1. マニフェスト必須項目の妥当性 (JSON Schema バリデーション)。
  2. `_manifest.json` に記載された `records` と実際の行数が一致。
  3. ハッシュ値が一致し、転送破損がない。
- 不備があれば `logs/validation/` に結果を出力し、Slack 通知。

## 決定事項 / 未決事項
- **決定事項**
  - raw 層は `yyyymm=<YYYY-MM>` のパーティションディレクトリを採用し、file_type ごとにフォルダを分割する。
  - `_manifest.json` の必須項目は `yyyymm`, `file_type`, `facility_cd`, `records`, `hash`, `created_at` とする。
  - raw データは 13 か月で archive へ移動、archive は 5 年後に Glacier Deep Archive へ移行する。
- **未決事項**
  - ライフサイクル移動後の復元 SLA（応答時間）をどの程度に設定するか検討が必要。
  - `_manifest.json` の `notes` 項目に含める共通メタ情報（例: 締め処理担当者 ID）の標準化が未確定。
  - 施設ごとに複数ファイルが存在する場合の `seq` 命名ルール（ゼロパディング桁数）の最終合意が必要。
