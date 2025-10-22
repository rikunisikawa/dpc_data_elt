# Pipeline Module

This Terraform module provisions the minimal ELT orchestration plane described in
[`plans/minimal_task_03_pipeline.md`](../../plans/minimal_task_03_pipeline.md).
It wires together Step Functions, Lambda, ECS on Fargate, EventBridge, and SNS
so the nightly load documented in `docs/07_elt_pipeline.md` can be exercised in a
learning environment.

## Components

The module creates the following building blocks:

- Five Lambda functions (`dpc-validate-manifest`, `dpc-copy-raw`,
  `dpc-compute-readmit`, `dpc-export-parquet`, `dpc-notify`) that share a common
  execution role and optional Lambda layers.
- An SNS topic with a Lambda subscription so notifications emitted by
  `dpc-notify` can be fanned out to other channels (for example Slack via
  Secrets Manager).
- An ECR repository plus an ECS task definition used to execute dbt commands on
  AWS Fargate with Redshift credentials supplied from Secrets Manager.
- An AWS Step Functions state machine that mirrors the `Validate → Copy →
  Compute → dbt → Export → Notify` flow, including a `RollbackStage` `Pass`
  state that surfaces potential TRUNCATE statements through Terraform variables.
- An EventBridge rule/target pair that kicks off the state machine on a schedule
  and an IAM policy that allows operators to start the flow manually.

## Usage

````hcl
module "pipeline" {
  source = "./modules/pipeline"

  tags                   = { project = "dpc-learning" }
  lambda_package_bucket  = var.lambda_package_bucket
  lambda_role_arn        = aws_iam_role.lambda.arn
  lambda_layers          = [aws_lambda_layer_version.common.arn]
  notify_slack_secret_arn = aws_secretsmanager_secret.slack.arn
  redshift_secret_arn     = aws_secretsmanager_secret.redshift.arn
  export_parquet_target_bucket = aws_s3_bucket.processed.bucket

  lambda_functions = {
    validate_manifest = {
      handler     = "app.handler"
      runtime     = "python3.11"
      package_key = "lambda/dpc-validate-manifest.zip"
    }
    copy_raw = {
      handler     = "app.handler"
      runtime     = "python3.11"
      package_key = "lambda/dpc-copy-raw.zip"
    }
    compute_readmit = {
      handler     = "app.handler"
      runtime     = "python3.11"
      package_key = "lambda/dpc-compute-readmit.zip"
    }
    export_parquet = {
      handler     = "app.handler"
      runtime     = "python3.11"
      package_key = "lambda/dpc-export-parquet.zip"
    }
    notify = {
      handler     = "app.handler"
      runtime     = "python3.11"
      package_key = "lambda/dpc-notify.zip"
    }
  }

  sns_topic_name                = "dpc-pipeline-notifications"
  state_machine_name            = "dpc-elt-pipeline"
  state_machine_role_arn        = aws_iam_role.step_functions.arn
  eventbridge_schedule_expression = "cron(0 2 * * ? *)"
  eventbridge_role_arn            = aws_iam_role.events_to_sfn.arn

  ecs_cluster_arn        = aws_ecs_cluster.main.arn
  ecs_subnet_ids         = module.network.private_subnet_ids
  ecs_security_group_ids = [aws_security_group.ecs.id]
  dbt_execution_role_arn = aws_iam_role.ecs_execution.arn
  dbt_task_role_arn      = aws_iam_role.ecs_task.arn
}
````

Only the Lambda handler, runtime, and deployment package S3 keys are required
for each function. Optional inputs allow you to override memory, timeout,
command/arguments for dbt, additional environment variables, or the Step
Functions notification payload.

### Step Functions definition

The generated state machine uses `arn:aws:states:::lambda:invoke` for Lambda
steps and `arn:aws:states:::ecs:runTask.sync` for the dbt stage. Failures in the
`CopyRaw`, `ComputeReadmit`, and ECS stages transition to `RollbackStage`, which
is expressed as a `Pass` state that only records whether TRUNCATE statements
should run before the next attempt. The value is controlled by
`var.enable_rollback_truncate` and `var.rollback_statements` so destructive
changes remain opt-in in the training environment.

### Notifications

By default the same `dpc-notify` function is invoked directly from Step
Functions and can also be triggered by SNS publications. The module injects the
Slack webhook secret ARN automatically when `var.notify_slack_secret_arn` is
set, allowing the Lambda implementation to fetch credentials from Secrets
Manager and call incoming webhooks.

### dbt execution

The ECS task definition produces a single-container Fargate task. Environment
variables defined through `var.dbt_environment_defaults` and
`var.dbt_environment_overrides` are baked into the task definition, while
`var.dbt_state_machine_environment` can push runtime values (static strings or
state paths) through Step Functions overrides.

### Outputs

| Output | Description |
| ------ | ----------- |
| `lambda_function_arns` | Map of Lambda function ARNs keyed by logical name. |
| `sns_topic_arn` | Notification topic ARN for pipeline alerts. |
| `dbt_repository_url` | ECR repository URL for the dbt runner image. |
| `dbt_task_definition_arn` | ECS task definition ARN for Fargate executions. |
| `state_machine_arn` | Step Functions state machine ARN. |
| `event_rule_arn` | EventBridge rule ARN for scheduled executions. |
| `manual_start_policy_arn` | IAM policy ARN that grants manual start privileges. |

> **Note:** SNS subscriptions and CloudWatch alarms are managed by
> [`modules/operations`](../operations/README.md) so that alerting
> configuration lives alongside the broader operations tooling.
