# DPC 学習基盤 ネットワーク & セキュリティ設計

## 目的
Amazon VPC 内で Redshift と Lambda を中心とする DPC 学習基盤の接続形態、暗号化、権限管理を定義し、セキュリティ要件を満たす。

## ネットワーク概要
| 項目 | 設定方針 |
| --- | --- |
| VPC CIDR | 10.20.0.0/16 |
| アベイラビリティゾーン | ap-northeast-1a / 1c |
| サブネット構成 | Private Subnet (Redshift 用) ×1、Private Subnet (Lambda 用) ×2、共有 Services Subnet ×1 |
| ルーティング | Private Subnet → NAT Gateway（1a） → Internet Gateway（アウトバウンド最小）、S3 は Gateway エンドポイント経由 |
| VPC エンドポイント | S3 Gateway、Redshift Data API Interface、Secrets Manager Interface、CloudWatch Logs Interface |
| DNS | Route 53 Resolver、VPC 内プライベートホストゾーンで Redshift エンドポイント参照 |

### トポロジ図（文章）
- **Subnet-Analytics-1a (10.20.1.0/24)**: Redshift メインノード、Step Functions エンドポイント接続。SG で 5439/TCP を Lambda からのみに許可。
- **Subnet-Lambda-1a (10.20.11.0/24)**、**Subnet-Lambda-1c (10.20.21.0/24)**: Lambda 関数（dbt Runner / Manifest Validator）を配置。アウトバウンドは VPC エンドポイントと NAT Gateway のみに制限。
- **Subnet-Services-1a (10.20.31.0/24)**: NAT Gateway、Interface エンドポイントを配置。

## NAT とエンドポイント
| コンポーネント | 用途 | 備考 |
| --- | --- | --- |
| NAT Gateway | Lambda が外部パッケージを pip install する場合に使用。通常は CI/CD に限定し最小利用。 |
| S3 Gateway Endpoint | raw/stage/processed/archive バケットへのプライベートアクセス。Route Table にプレフィックスリストを追加。 |
| Redshift Data API Interface Endpoint | Lambda → Redshift Data API 通信をプライベート化。 |
| Secrets Manager Interface Endpoint | Lambda/Step Functions からの Secrets 取得。 |
| CloudWatch Logs Interface Endpoint | Lambda/Step Functions のログ出力。 |

## セキュリティ設定
### セキュリティグループ
| SG 名称 | 適用リソース | 受信 | 送信 |
| --- | --- | --- | --- |
| sg-redshift | Redshift RA3 | Lambda SG からの TCP/5439 のみ | すべて許可（デフォルト） |
| sg-lambda | Lambda Functions | なし | VPC エンドポイント、NAT Gateway のみ（TCP/443） |
| sg-endpoint | Interface VPC Endpoint | Lambda SG からの TCP/443 | なし |

### ネットワーク ACL
- Private Subnet は既定の許可ルールを使用しつつ、外部アクセス源を自社 IP 範囲に限定。
- NAT Subnet の入出力を最小限 (80/443) に制限。

## 暗号化
| 対象 | 手段 |
| --- | --- |
| S3 バケット | SSE-KMS (`alias/dpc-learning-kms`)、バケットポリシーで HTTPS を強制。 |
| Redshift | クラスター暗号化 (KMS CMK) を有効化。ディスク暗号化 + Snapshots 暗号化。 |
| Transit | VPC 内通信は TLS を必須（Redshift、S3 Transfer Acceleration は利用しない）。Lambda からの外部通信は `requests` で TLS1.2 以上。 |
| Secrets | Secrets Manager + KMS。Lambda 実行時に環境変数ではなく Secrets を参照。 |

## IAM ロールとポリシー
### IAM ロール一覧
| ロール | 想定エンティティ | 主な権限 |
| --- | --- | --- |
| `role-lambda-dpc` | Lambda | S3 raw/stage 読み書き、Redshift Data API、Secrets、CloudWatch Logs |
| `role-stepfunctions-dpc` | Step Functions | Lambda Invoke、SNS Publish、CloudWatch Logs |
| `role-redshift-copy` | Redshift | S3 バケット読み取り、KMS decrypt、CloudWatch Logs |
| `role-dbt-runner` | dbt 実行環境 (CodeBuild など) | Redshift SQL 実行、S3 artifacts 書込 |
| `role-dq-analytics` | DQ Lambda | Redshift Data API 実行、Slack Webhook 呼出（Secrets 経由） |

### IAM ポリシー（JSON スケルトン）
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3RawAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::dpc-learning-data-<env>",
        "arn:aws:s3:::dpc-learning-data-<env>/raw/*"
      ]
    },
    {
      "Sid": "RedshiftDataApi",
      "Effect": "Allow",
      "Action": [
        "redshift-data:ExecuteStatement",
        "redshift-data:GetStatementResult",
        "redshift-data:CancelStatement"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SecretsAccess",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:ap-northeast-1:<account>:secret:dpc/*"
    },
    {
      "Sid": "KMSDecrypt",
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ],
      "Resource": "arn:aws:kms:ap-northeast-1:<account>:key/<kms-id>"
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:ap-northeast-1:<account>:*"
    }
  ]
}
```

必要に応じて、POLICY の `Resource` を最小権限に調整する。

## 監査ログ設計
| ログ種別 | 送信先 | 保管期間 |
| --- | --- | --- |
| CloudTrail (管理イベント + データイベント S3) | CloudTrail Organization Trail → S3 `logs/cloudtrail/` | 365 日 |
| Redshift Audit Log | CloudWatch Logs (`/aws/redshift/cluster/dpc-learning`) → S3 Export (月次) | 365 日 |
| Step Functions / Lambda Logs | CloudWatch Logs (`/aws/states/dpc-learning`, `/aws/lambda/dpc-*`) | 180 日 |
| S3 Access Logs | CloudTrail S3 データイベントで代替。必要に応じて S3 Server Access Log を archive/ 配下に保存。 |

## TLS 設定
- Redshift: `require_ssl` パラメータを true。Lambda からは JDBC/psycopg ではなく Redshift Data API (TLS 強制) を使用。
- QuickSight 接続: SSL/TLS を強制。VPC 接続で PrivateLink。

## 決定事項 / 未決事項
- **決定事項**
  - Redshift / Lambda は同一 VPC に配置し、すべてプライベートサブネットで構成する。
  - S3 へのアクセスは Gateway VPC Endpoint を通過し、IAM ポリシーで IP / VPC 条件を付与する。
  - Secrets は Secrets Manager に統一し、環境変数への埋め込みは禁止する。
- **未決事項**
  - NAT Gateway を常設するか、CI/CD 実行時のみ有効化するかはコストと運用を踏まえて調整が必要。
  - Redshift Data API ではなく JDBC 接続を併用する場合のクライアント IP 制御が未検討。
  - CloudTrail ログの集中管理（組織アカウント）に参加するかどうかをセキュリティチームと協議する必要がある。
