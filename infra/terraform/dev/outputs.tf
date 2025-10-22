output "step_functions_alarm_arn" {
  description = "ARN of the CloudWatch alarm configured for Step Functions failures."
  value       = module.operations.step_functions_alarm_arn
}

output "redshift_rpu_alarm_arn" {
  description = "ARN of the CloudWatch alarm configured for Redshift RPU utilization."
  value       = module.operations.redshift_rpu_alarm_arn
}
