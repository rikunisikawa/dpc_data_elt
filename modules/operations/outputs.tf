output "step_functions_alarm_arn" {
  description = "ARN of the CloudWatch alarm monitoring Step Functions failures."
  value       = aws_cloudwatch_metric_alarm.step_functions_failed.arn
}

output "redshift_rpu_alarm_arn" {
  description = "ARN of the CloudWatch alarm monitoring Redshift RPU utilization."
  value       = aws_cloudwatch_metric_alarm.redshift_rpu_utilization.arn
}

output "sns_lambda_subscription_arn" {
  description = "ARN of the SNS subscription that invokes the notify Lambda."
  value       = aws_sns_topic_subscription.notify_lambda.arn
}

output "sns_email_subscription_arns" {
  description = "Map of email addresses to their SNS subscription ARNs."
  value       = { for email, subscription in aws_sns_topic_subscription.email : email => subscription.arn }
}
