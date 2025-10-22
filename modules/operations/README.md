# Operations Monitoring Module

This Terraform module provisions a minimal set of CloudWatch alarms and notification plumbing for the DPC learning platform. It focuses on two critical signals:

- **Step Functions execution failures** using the `ExecutionsFailed` metric.
- **Redshift Serverless RPU utilization** to detect sustained capacity pressure.

All alerts fan out through the existing `dpc-learning-alerts` SNS topic so they can reach Slack via the `dpc-notify` Lambda function and optional email subscribers.

## Usage

```hcl
module "operations" {
  source = "./modules/operations"

  environment                  = var.environment
  tags                         = local.tags
  sns_topic_arn                = module.pipeline.sns_topic_arn
  notify_lambda_arn            = module.pipeline.lambda_function_arns["notify"]
  state_machine_arn            = module.pipeline.state_machine_arn
  redshift_workgroup_name      = var.redshift_workgroup_name
  email_subscribers            = ["alerts@example.com"]
  send_ok_actions              = true
  redshift_rpu_utilization_threshold = 85
}
```

## Inputs

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `environment` | Environment identifier used for alarm naming (e.g. `dev`, `stg`, `prod`). | `string` | n/a | yes |
| `tags` | Additional tags applied to alarm resources. | `map(string)` | `{}` | no |
| `sns_topic_arn` | ARN of the SNS topic that fan-outs operations alerts. | `string` | n/a | yes |
| `sns_raw_message_delivery` | Enables raw SNS message delivery for the Lambda subscription. | `bool` | `false` | no |
| `email_delivery_policy` | Optional SNS delivery policy JSON applied to each email subscription. | `string` | `null` | no |
| `notify_lambda_arn` | ARN of the `dpc-notify` Lambda function. | `string` | n/a | yes |
| `email_subscribers` | Email addresses that should receive alert notifications. | `list(string)` | `[]` | no |
| `state_machine_arn` | ARN of the Step Functions state machine monitored for failures. | `string` | n/a | yes |
| `step_functions_failure_threshold` | Number of failed executions that triggers the alarm. | `number` | `1` | no |
| `step_functions_evaluation_periods` | Number of periods evaluated for the Step Functions alarm. | `number` | `1` | no |
| `step_functions_datapoints_to_alarm` | Datapoints that must breach for the Step Functions alarm to trigger. | `number` | `1` | no |
| `step_functions_period_seconds` | Evaluation period (seconds) for the Step Functions metric. | `number` | `300` | no |
| `step_functions_treat_missing_data` | Treatment of missing data for the Step Functions alarm. | `string` | `"notBreaching"` | no |
| `redshift_workgroup_name` | Redshift Serverless workgroup name monitored for RPU utilization. | `string` | n/a | yes |
| `redshift_rpu_utilization_threshold` | Average RPU utilization percentage that triggers the alarm. | `number` | `80` | no |
| `redshift_rpu_evaluation_periods` | Number of periods evaluated for the Redshift alarm. | `number` | `1` | no |
| `redshift_rpu_datapoints_to_alarm` | Datapoints that must breach for the Redshift alarm to trigger. | `number` | `1` | no |
| `redshift_rpu_period_seconds` | Evaluation period (seconds) for the Redshift metric. | `number` | `300` | no |
| `redshift_rpu_treat_missing_data` | Treatment of missing data for the Redshift alarm. | `string` | `"notBreaching"` | no |
| `send_ok_actions` | When true, send recovery notifications to the same SNS topic. | `bool` | `false` | no |

## Outputs

| Name | Description |
| --- | --- |
| `step_functions_alarm_arn` | ARN of the CloudWatch alarm for Step Functions failures. |
| `redshift_rpu_alarm_arn` | ARN of the CloudWatch alarm for Redshift RPU utilization. |
| `sns_lambda_subscription_arn` | ARN of the SNS subscription that invokes the notify Lambda. |
| `sns_email_subscription_arns` | Map of email addresses to their SNS subscription ARNs. |
