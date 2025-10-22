output "kms_key_arn" {
  description = "ARN of the customer managed CMK used for platform encryption."
  value       = module.foundation.kms_key_arn
}

output "data_bucket_name" {
  description = "Name of the S3 bucket for DPC data layers."
  value       = module.foundation.data_bucket_name
}

output "iam_role_arns" {
  description = "Key IAM role ARNs provisioned for the learning platform."
  value = {
    lambda         = module.iam.role_lambda_arn
    stepfunctions  = module.iam.role_stepfunctions_arn
    redshift_copy  = module.iam.role_redshift_copy_arn
  }
}
