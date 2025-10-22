output "role_lambda_arn" {
  description = "Execution role ARN for Lambda functions."
  value       = aws_iam_role.lambda.arn
}

output "role_stepfunctions_arn" {
  description = "Execution role ARN for Step Functions state machines."
  value       = aws_iam_role.stepfunctions.arn
}

output "role_redshift_copy_arn" {
  description = "IAM role ARN assumed by Redshift for COPY/UNLOAD operations."
  value       = aws_iam_role.redshift_copy.arn
}
