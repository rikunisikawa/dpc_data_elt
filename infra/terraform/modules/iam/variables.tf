variable "env" {
  description = "Environment suffix used for logging and tagging."
  type        = string
}

variable "bucket_arn" {
  description = "ARN of the S3 bucket that stores platform data."
  type        = string
}

variable "bucket_name" {
  description = "Name of the S3 bucket that stores platform data."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used for platform encryption."
  type        = string
}

variable "tags" {
  description = "Tags to apply to IAM resources."
  type        = map(string)
  default     = {}
}
