variable "tags" {
  description = "Common tags applied to all taggable resources."
  type        = map(string)
  default     = {}
}

variable "lambda_package_bucket" {
  description = "S3 bucket that stores Lambda deployment packages."
  type        = string
}

variable "lambda_role_arn" {
  description = "IAM role ARN assumed by the Lambda functions in the pipeline."
  type        = string
}

variable "lambda_layers" {
  description = "List of Lambda layer ARNs shared across pipeline functions."
  type        = list(string)
  default     = []
}

variable "lambda_default_timeout" {
  description = "Default timeout (in seconds) applied to Lambda functions when not specified individually."
  type        = number
  default     = 300
}

variable "lambda_default_memory_size" {
  description = "Default memory size (in MB) for Lambda functions when not specified individually."
  type        = number
  default     = 512
}

variable "lambda_environment_defaults" {
  description = "Environment variables merged into every Lambda function in the pipeline."
  type        = map(string)
  default     = {}
}

variable "notify_slack_secret_arn" {
  description = "Secrets Manager ARN that stores the Slack webhook for notifications. When provided it is injected into the notify Lambda function as SLACK_WEBHOOK_SECRET_ARN."
  type        = string
  default     = ""
}

variable "redshift_secret_arn" {
  description = "Secrets Manager ARN that stores the Redshift credentials. Injected into the compute/readmit Lambda and dbt task environment when provided."
  type        = string
  default     = ""
}

variable "export_parquet_target_bucket" {
  description = "Default bucket name used by the export parquet Lambda. When supplied it is added as TARGET_BUCKET environment variable."
  type        = string
  default     = ""
}

variable "lambda_functions" {
  description = <<DESC
Map describing the Lambda functions that compose the ELT pipeline. The keys must include
`validate_manifest`, `copy_raw`, `compute_readmit`, `export_parquet`, and `notify`.
Each object accepts the following attributes:
  * function_name  - Optional explicit Lambda function name. Defaults to `dpc-<key>`.
  * description    - Optional description for the Lambda function.
  * handler        - Lambda handler string.
  * runtime        - Lambda runtime identifier.
  * package_key    - S3 object key that contains the deployment package zip file.
  * source_code_hash - Optional base64-encoded deployment package hash.
  * timeout        - Optional override timeout in seconds.
  * memory_size    - Optional override memory size in MB.
  * environment    - Optional map of extra environment variables specific to the function.
DESC
  type = map(object({
    function_name    = optional(string)
    description      = optional(string)
    handler          = string
    runtime          = string
    package_key      = string
    source_code_hash = optional(string)
    timeout          = optional(number)
    memory_size      = optional(number)
    environment      = optional(map(string), {})
  }))

  validation {
    condition = alltrue([
      for required in ["validate_manifest", "copy_raw", "compute_readmit", "export_parquet", "notify"] :
      contains(keys(var.lambda_functions), required)
    ])
    error_message = "lambda_functions must include validate_manifest, copy_raw, compute_readmit, export_parquet, and notify entries."
  }
}

variable "lambda_publish" {
  description = "Whether to publish a new version on each Lambda deployment."
  type        = bool
  default     = false
}

variable "sns_topic_name" {
  description = "Name of the SNS topic that aggregates pipeline notifications."
  type        = string
}

variable "state_machine_name" {
  description = "Name assigned to the Step Functions state machine."
  type        = string
}

variable "state_machine_role_arn" {
  description = "IAM role ARN assumed by the Step Functions state machine."
  type        = string
}

variable "state_machine_comment" {
  description = "Optional comment stored in the Step Functions definition for documentation."
  type        = string
  default     = "DPC ELT pipeline"
}

variable "enable_rollback_truncate" {
  description = "When true the RollbackStage result indicates that downstream processes should perform TRUNCATE operations before a retry."
  type        = bool
  default     = false
}

variable "rollback_statements" {
  description = "Optional list of SQL statements that would be executed during rollback in a production deployment. They are surfaced as metadata in the Pass state."
  type        = list(string)
  default     = []
}

variable "eventbridge_schedule_expression" {
  description = "Schedule expression that triggers the daily pipeline execution via EventBridge."
  type        = string
}

variable "eventbridge_role_arn" {
  description = "IAM role ARN used by EventBridge to start the Step Functions execution."
  type        = string
}

variable "eventbridge_input" {
  description = "Static JSON payload provided when EventBridge starts the pipeline."
  type        = map(any)
  default     = {}
}

variable "dbt_repository_name" {
  description = "Name of the ECR repository that stores the dbt runner container image."
  type        = string
  default     = "dpc-dbt-runner"
}

variable "dbt_repository_force_delete" {
  description = "Whether to allow Terraform to delete the ECR repository even when images are present."
  type        = bool
  default     = false
}

variable "dbt_task_family" {
  description = "Family name for the dbt ECS task definition."
  type        = string
  default     = "dpc-dbt-runner"
}

variable "dbt_task_cpu" {
  description = "CPU units allocated to the dbt ECS task."
  type        = number
  default     = 1024
}

variable "dbt_task_memory" {
  description = "Memory (in MiB) allocated to the dbt ECS task."
  type        = number
  default     = 2048
}

variable "dbt_execution_role_arn" {
  description = "IAM execution role ARN used by the dbt ECS task definition."
  type        = string
}

variable "dbt_task_role_arn" {
  description = "IAM task role ARN that grants the dbt container access to the Data API and Secrets Manager."
  type        = string
}

variable "dbt_container_name" {
  description = "Name assigned to the dbt container within the ECS task definition."
  type        = string
  default     = "dbt-runner"
}

variable "dbt_container_image" {
  description = "Full image URI for the dbt container. When empty the module references the repository created within this module."
  type        = string
  default     = ""
}

variable "dbt_container_command" {
  description = "Default command baked into the dbt task definition. The Step Functions task can override this at runtime."
  type        = list(string)
  default     = ["dbt", "run"]
}

variable "dbt_environment_defaults" {
  description = "Environment variables embedded in the dbt container definition."
  type        = map(string)
  default     = {}
}

variable "dbt_environment_overrides" {
  description = "Additional environment variables merged into the dbt container definition."
  type        = map(string)
  default     = {}
}

variable "dbt_state_machine_command" {
  description = "Command executed by the ECS RunTask state within Step Functions."
  type        = list(string)
  default     = ["dbt", "run"]
}

variable "dbt_state_machine_environment" {
  description = "Additional environment overrides supplied by the Step Functions RunTask state. Set value for static literals or value_path to reference the state input."
  type = list(object({
    name       = string
    value      = optional(string)
    value_path = optional(string)
  }))
  default = []

  validation {
    condition = length(var.dbt_state_machine_environment) == 0 ? true : alltrue([
      for item in var.dbt_state_machine_environment : (
        (try(item.value, null) != null && try(item.value_path, null) == null) ||
        (try(item.value, null) == null && try(item.value_path, null) != null)
      )
    ])
    error_message = "Each dbt_state_machine_environment entry must define exactly one of value or value_path."
  }
}

variable "dbt_log_configuration" {
  description = "Optional log configuration block injected into the dbt container definition."
  type        = any
  default     = null
}

variable "ecs_cluster_arn" {
  description = "ARN of the ECS cluster where the dbt task runs."
  type        = string
}

variable "ecs_subnet_ids" {
  description = "Subnet IDs assigned to the Fargate task network configuration."
  type        = list(string)
}

variable "ecs_security_group_ids" {
  description = "Security group IDs attached to the Fargate task."
  type        = list(string)
}

variable "ecs_assign_public_ip" {
  description = "When true the ECS task receives a public IP address."
  type        = bool
  default     = false
}

variable "manual_start_policy_name" {
  description = "Name of the IAM policy that grants operators access to manually start the pipeline."
  type        = string
  default     = "dpc-pipeline-manual-start"
}
