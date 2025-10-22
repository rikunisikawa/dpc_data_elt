output "step_functions_alarm_arn" {
  description = "ARN of the CloudWatch alarm that monitors Step Functions execution failures."
  value       = aws_cloudwatch_metric_alarm.step_functions_failed.arn
}

output "redshift_rpu_alarm_arn" {
  description = "ARN of the CloudWatch alarm that monitors Redshift Serverless RPU utilization."
  value       = aws_cloudwatch_metric_alarm.redshift_rpu.arn
}

output "lambda_subscription_arn" {
  description = "ARN of the Lambda subscription that receives SNS notifications."
  value       = var.lambda_subscription_arn
  sensitive   = true
}

output "email_subscription_endpoints" {
  description = "List of email addresses subscribed to the alert topic."
  value       = [for subscription in aws_sns_topic_subscription.email : subscription.endpoint]
}
