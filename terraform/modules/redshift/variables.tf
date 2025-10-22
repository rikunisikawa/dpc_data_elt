variable "workgroup_name" {
  description = "Name of the Redshift Serverless workgroup."
  type        = string
}

variable "namespace_name" {
  description = "Name of the Redshift Serverless namespace."
  type        = string
}

variable "database_name" {
  description = "Default database name to create in the namespace."
  type        = string
}

variable "base_capacity" {
  description = "Compute capacity for the workgroup (in RPUs)."
  type        = number
}

variable "snapshot_retention_period" {
  description = "Number of days to retain automatic snapshots."
  type        = number
}

variable "subnet_ids" {
  description = "Subnet IDs for the Redshift workgroup."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs attached to the workgroup."
  type        = list(string)
}

variable "copy_role_arn" {
  description = "IAM role ARN with COPY/UNLOAD permissions."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN used to encrypt the namespace."
  type        = string
}

variable "log_exports" {
  description = "Log exports enabled on the namespace."
  type        = list(string)
}

variable "manage_admin_password" {
  description = "Whether to allow Redshift to manage the admin password."
  type        = bool
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "namespace_tags" {
  description = "Additional tags for the namespace resource."
  type        = map(string)
  default     = {}
}

variable "workgroup_tags" {
  description = "Additional tags for the workgroup resource."
  type        = map(string)
  default     = {}
}
