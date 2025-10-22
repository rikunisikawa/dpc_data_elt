# DPC 学習基盤 ミニマム実装タスク一覧

本セットは docs/01_architecture.md ～ docs/13_data_export.md に記載された要件のうち、学習環境で最小限のデータ基盤を完成させるための実装手順を抽出したものです。詳細ステップは個別タスク文書を参照してください。

## タスク一覧
1. [Terraform での AWS 基盤初期設定](./minimal_task_01_foundation.md)
2. [Redshift Serverless とスキーマ準備](./minimal_task_02_redshift.md)
3. [Step Functions / Lambda / ECS による ELT パイプライン構築](./minimal_task_03_pipeline.md)
4. [dbt プロジェクトの初期化](./minimal_task_04_dbt.md)
5. [S3 命名規約と手動取込運用の整備](./minimal_task_05_ingestion.md)
6. [データ品質チェックの最小構成](./minimal_task_06_data_quality.md)
7. [運用監視と通知のセットアップ](./minimal_task_07_operations.md)
8. [エクスポートと可視化準備](./minimal_task_08_export_reporting.md)

## 進め方
- 上から順に実施すると、Terraform でのインフラ構築 → DWH → パイプライン → モデル → データ品質 → 運用 → 出力の順で基盤が完成します。
- 追加ログ収集や高度なセキュリティ統制は scope 外です。必要になった時点で別途拡張してください。
- 各タスク文書の「完了条件」を満たしたら次のタスクに進みます。
