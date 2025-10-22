output "kms_key_arn" {
  description = "ARN of the customer managed CMK."
  value       = aws_kms_key.dpc.arn
}

output "kms_key_id" {
  description = "Key ID of the customer managed CMK."
  value       = aws_kms_key.dpc.key_id
}

output "data_bucket_name" {
  description = "Name of the S3 bucket hosting DPC datasets."
  value       = aws_s3_bucket.data.bucket
}

output "data_bucket_arn" {
  description = "ARN of the S3 bucket hosting DPC datasets."
  value       = aws_s3_bucket.data.arn
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail recording platform activity."
  value       = aws_cloudtrail.dpc.arn
}
