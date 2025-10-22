variable "aws_region" {
  description = "AWS region used by the development environment."
  type        = string
  default     = "ap-northeast-1"
}

variable "environment" {
  description = "Logical environment name propagated to modules."
  type        = string
  default     = "dev"
}

variable "default_tags" {
  description = "Default tags applied to Terraform-managed resources."
  type        = map(string)
  default = {
    Project = "dpc-learning"
  }
}
