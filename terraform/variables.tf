variable "aws_region" {
  description = "AWS region where resources will be created."
  type        = string
  default     = "ap-northeast-1"
}

variable "copy_role_name" {
  description = "Name of the IAM role that Redshift uses for COPY and UNLOAD operations."
  type        = string
  default     = "role-redshift-copy"
}

variable "kms_alias_name" {
  description = "KMS key alias used to encrypt the Redshift Serverless namespace."
  type        = string
  default     = "alias/dpc-learning-kms"
}

variable "workgroup_name" {
  description = "Name of the Redshift Serverless workgroup."
  type        = string
  default     = "dpc-learning-wg"
}

variable "namespace_name" {
  description = "Name of the Redshift Serverless namespace."
  type        = string
  default     = "dpc-learning-ns"
}

variable "database_name" {
  description = "Default database name for the namespace."
  type        = string
  default     = "dpc_learning"
}

variable "base_capacity" {
  description = "Base capacity (RPU) for the Redshift Serverless workgroup."
  type        = number
  default     = 8
}

variable "snapshot_retention_period" {
  description = "Automatic snapshot retention period in days."
  type        = number
  default     = 7
}

variable "log_exports" {
  description = "List of log exports to enable for the namespace."
  type        = list(string)
  default     = ["userlog", "connectionlog", "useractivitylog"]
}

variable "manage_admin_password" {
  description = "Whether Redshift should manage the admin password for the namespace."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to shared resources."
  type        = map(string)
  default = {
    Project = "dpc-learning"
    Stack   = "minimal"
  }
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
