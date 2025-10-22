variable "env" {
  description = "Environment suffix for tagging consistency."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt secrets."
  type        = string
}

variable "tags" {
  description = "Tags to apply to secrets resources."
  type        = map(string)
  default     = {}
}
