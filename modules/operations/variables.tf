variable "environment" {
  description = "Environment identifier used for alarm naming (e.g. dev, stg, prod)."
  type        = string
}

variable "tags" {
  description = "Additional tags applied to alarm resources."
  type        = map(string)
  default     = {}
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic that fan-outs operations alerts."
  type        = string
}

variable "sns_raw_message_delivery" {
  description = "Whether to enable raw message delivery for the Lambda SNS subscription."
  type        = bool
  default     = false
}

variable "email_delivery_policy" {
  description = "Optional SNS delivery policy JSON for email subscriptions."
  type        = string
  default     = null
}

variable "notify_lambda_arn" {
  description = "ARN of the dpc-notify Lambda function that relays alerts to Slack."
  type        = string
}

variable "email_subscribers" {
  description = "List of email addresses that should receive alert notifications."
  type        = list(string)
  default     = []
}

variable "state_machine_arn" {
  description = "ARN of the Step Functions state machine monitored for failed executions."
  type        = string
}

variable "step_functions_failure_threshold" {
  description = "Number of failed executions that triggers the alarm."
  type        = number
  default     = 1
}

variable "step_functions_evaluation_periods" {
  description = "Number of periods to evaluate for the Step Functions failure alarm."
  type        = number
  default     = 1
}

variable "step_functions_datapoints_to_alarm" {
  description = "Number of datapoints that must breach the threshold to trigger the Step Functions alarm."
  type        = number
  default     = 1
}

variable "step_functions_period_seconds" {
  description = "Period, in seconds, over which the Step Functions metric is evaluated."
  type        = number
  default     = 300
}

variable "step_functions_treat_missing_data" {
  description = "How missing data is treated for the Step Functions alarm."
  type        = string
  default     = "notBreaching"
}

variable "redshift_workgroup_name" {
  description = "Name of the Redshift Serverless workgroup monitored for RPU utilization."
  type        = string
}

variable "redshift_rpu_utilization_threshold" {
  description = "Average RPU utilization percentage that triggers the alarm."
  type        = number
  default     = 80
}

variable "redshift_rpu_evaluation_periods" {
  description = "Number of periods to evaluate for the Redshift RPU alarm."
  type        = number
  default     = 1
}

variable "redshift_rpu_datapoints_to_alarm" {
  description = "Number of datapoints that must breach the threshold to trigger the Redshift alarm."
  type        = number
  default     = 1
}

variable "redshift_rpu_period_seconds" {
  description = "Period, in seconds, over which the Redshift RPU metric is evaluated."
  type        = number
  default     = 300
}

variable "redshift_rpu_treat_missing_data" {
  description = "How missing data is treated for the Redshift RPU alarm."
  type        = string
  default     = "notBreaching"
}

variable "send_ok_actions" {
  description = "Whether to send OK notifications to the same SNS topic."
  type        = bool
  default     = false
}
