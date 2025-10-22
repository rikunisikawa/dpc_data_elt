output "lambda_function_arns" {
  description = "Map of Lambda function ARNs keyed by their logical name."
  value       = { for name, fn in aws_lambda_function.pipeline : name => fn.arn }
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic used for pipeline notifications."
  value       = aws_sns_topic.pipeline.arn
}

output "sns_subscription_arn" {
  description = "ARN of the Lambda subscription attached to the notification topic."
  value       = aws_sns_topic_subscription.notify.arn
}

output "dbt_repository_url" {
  description = "URL of the ECR repository that stores the dbt runner image."
  value       = aws_ecr_repository.dbt.repository_url
}

output "dbt_task_definition_arn" {
  description = "ARN of the ECS task definition that executes dbt commands."
  value       = aws_ecs_task_definition.dbt.arn
}

output "state_machine_arn" {
  description = "ARN of the Step Functions state machine orchestrating the ELT pipeline."
  value       = aws_sfn_state_machine.pipeline.arn
}

output "event_rule_arn" {
  description = "ARN of the EventBridge rule that schedules the pipeline execution."
  value       = aws_cloudwatch_event_rule.pipeline.arn
}

output "manual_start_policy_arn" {
  description = "ARN of the IAM policy that enables manual pipeline execution."
  value       = aws_iam_policy.manual_start.arn
}
