# DPC 学習基盤 ネットワーク & セキュリティ設計

## 目的
学習用途でコストを抑えることを重視しつつ、Redshift Serverless とサーバーレスコンポーネントの接続形態、暗号化、権限境界を定義する。

## ネットワーク概要
| 項目 | 設定方針 |
| --- | --- |
| VPC | 既定 VPC（10.0.0.0/16）を再利用。新規作成・運用コストを発生させない。|
| アベイラビリティゾーン | ap-northeast-1a / 1c のパブリックサブネットを Redshift Serverless ワークグループに割当。|
| サブネット構成 | ワークグループ用サブネットのみを指定。Lambda は VPC 外で実行し、追加サブネットを増やさない。|
| ルーティング | インターネットゲートウェイ経由。Redshift とは Data API 経由で通信するため、VPC 内に受信ルートを開放しない。|
| VPC エンドポイント | 初期構成では作成しない。必要になった時点で S3 Gateway などを追加検討。|
| DNS | 既定 VPC の DNS 解決を利用。プライベートホストゾーンは不要。|

### トポロジ図（文章）
- **Default Subnet (ap-northeast-1a)**: Redshift Serverless ワークグループのエンドポイントを割当。セキュリティグループで Data API 以外の接続を拒否。
- **Default Subnet (ap-northeast-1c)**: 冗長用に指定。ワークロード増加時のみ利用。
- **Lambda**: VPC 非参加で稼働。Redshift Data API、S3、Secrets Manager などはサービスエンドポイント経由でインターネット越しに TLS 接続する。

## NAT とエンドポイント
コスト削減のため初期構成では NAT Gateway や PrivateLink を作成しない。以下の方針で対応する。

| コンポーネント | 方針 |
| --- | --- |
| NAT Gateway | 未導入。Lambda コンテナイメージに依存ライブラリを内包し、実行時の外向き通信を避ける。|
| VPC エンドポイント | 追加費用が発生するため未作成。通信は AWS 管理の TLS エンドポイントを使用。|
| 将来拡張 | セキュリティ要件が強化された場合にのみ Interface/Gateway エンドポイントを追加。|

## セキュリティ設定
### セキュリティグループ
| SG 名称 | 適用リソース | 受信 | 送信 |
| --- | --- | --- | --- |
| sg-redshift-serverless | Redshift Serverless ワークグループ | 受信ルールは作成しない（Data API のみ利用）。 | 既定で許可 |

### ネットワーク ACL
- 既定 VPC の ACL を利用（全許可）。Data API を使用するため、IP 制限は IAM ポリシーとクレデンシャル管理で実施。

## 暗号化
| 対象 | 手段 |
| --- | --- |
| S3 バケット | SSE-KMS (`alias/dpc-learning-kms`)、バケットポリシーで HTTPS を強制。 |
| Redshift | Serverless ワークグループの暗号化を KMS CMK で有効化。スナップショットも自動暗号化。 |
| Transit | すべての通信は AWS 管理エンドポイントへの TLS1.2 以上。Lambda からの接続は Data API / S3 HTTPS のみ。 |
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

必要に応じて、POLICY の `Resource` を最小権限に調整する。Data API はリソース ARN が固定ではないため `Resource: "*"` を維持する。

## 監査ログ設計
| ログ種別 | 送信先 | 保管期間 |
| --- | --- | --- |
| CloudTrail (管理イベント + データイベント S3) | 単一アカウントの Trail を作成し、S3 `logs/cloudtrail/` へ出力 | 365 日 |
| Redshift Serverless 認証ログ | CloudWatch Logs (`/aws/redshift-serverless/workgroup/dpc-learning`) → S3 Export (月次) | 365 日 |
| Step Functions / Lambda Logs | CloudWatch Logs (`/aws/states/dpc-learning`, `/aws/lambda/dpc-*`) | 180 日 |
| S3 Access Logs | CloudTrail S3 データイベントで代替。必要に応じて S3 Server Access Log を archive/ 配下に保存。 |

## TLS 設定
- Redshift: Serverless ワークグループは自動で TLS を強制。JDBC 接続を許可する場合も SSL 設定を必須とする。
- QuickSight 接続: 直接 Redshift Serverless へ接続する場合は SSL/TLS を必須とし、必要であれば SPICE インポートで接続時間を短縮。

## 決定事項 / 未決事項
- **決定事項**
  - Redshift は Serverless ワークグループを使用し、既定 VPC のパブリックサブネットに割当てる。
  - Lambda は VPC 外で稼働し、NAT Gateway や VPC エンドポイントを導入しない。
  - Secrets は Secrets Manager に統一し、環境変数への埋め込みは禁止する。
  - JDBC 接続は利用せず、Redshift への操作は Data API のみとする。
  - CloudTrail は学習アカウント単独で運用し、組織トレイル連携は行わない。
  - Data API の利用者は学習者本人に限定し、追加ロール管理フローは構築しない。
- **未決事項**
  - 追加利用者が参加する場合のアクセス権限拡張手順は将来検討とする。
