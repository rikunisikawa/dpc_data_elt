output "step_functions_alarm_arn" {
  description = "ARN of the CloudWatch alarm that monitors Step Functions execution failures."
  value       = aws_cloudwatch_metric_alarm.step_functions_failed.arn
}

output "redshift_rpu_alarm_arn" {
  description = "ARN of the CloudWatch alarm that monitors Redshift Serverless RPU utilization."
  value       = aws_cloudwatch_metric_alarm.redshift_rpu.arn
}

output "lambda_permission_statement_id" {
  description = "Statement identifier granted for SNS to invoke the Lambda target."
  value       = try(aws_lambda_permission.allow_sns[0].statement_id, null)
}

output "email_subscription_endpoints" {
  description = "List of email addresses subscribed to the alert topic."
  value       = [for subscription in aws_sns_topic_subscription.email : subscription.endpoint]
}
