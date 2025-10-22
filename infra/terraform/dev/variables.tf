variable "environment" {
  description = "Deployment environment identifier (e.g. dev, stg, prod)."
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Additional tags to apply to all resources."
  type        = map(string)
  default     = {}
}
