variable "env" {
  description = "Environment suffix used for resource naming."
  type        = string
}

variable "tags" {
  description = "Tags to apply to foundation resources."
  type        = map(string)
  default     = {}
}
