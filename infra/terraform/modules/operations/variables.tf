variable "environment" {
  description = "Deployment environment identifier used in alarm names and descriptions."
  type        = string
}

variable "alarm_name_prefix" {
  description = "Optional prefix applied to all alarm names. Defaults to dpc-<environment> when not provided."
  type        = string
  default     = ""
}

variable "state_machine_arn" {
  description = "ARN of the Step Functions state machine to monitor for failed executions."
  type        = string
}

variable "step_functions_alarm_threshold" {
  description = "Number of failed Step Functions executions within the evaluation period that should trigger the alarm."
  type        = number
  default     = 1
}

variable "redshift_workgroup_name" {
  description = "Name of the Redshift Serverless workgroup to monitor for RPU utilization."
  type        = string
}

variable "redshift_rpu_threshold" {
  description = "Percentage of RPU utilization that should trigger the alarm."
  type        = number
  default     = 80
}

variable "alert_topic_arn" {
  description = "ARN of the SNS topic that forwards alerts to downstream subscribers."
  type        = string
}

variable "lambda_subscription_arn" {
  description = "ARN of the Lambda function (for example dpc-notify) that should receive SNS notifications."
  type        = string
  default     = null
}

variable "email_subscribers" {
  description = "Optional list of email addresses that should receive alarm notifications."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to supported resources created by this module."
  type        = map(string)
  default     = {}
}
