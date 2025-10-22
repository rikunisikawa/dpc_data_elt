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

variable "state_machine_arn" {
  description = "ARN of the Step Functions state machine executed by the ELT pipeline."
  type        = string
  default     = "arn:aws:states:ap-northeast-1:123456789012:stateMachine:dpc-learning-pipeline"
}

variable "alert_topic_arn" {
  description = "SNS topic ARN that delivers learning platform alerts."
  type        = string
  default     = "arn:aws:sns:ap-northeast-1:123456789012:dpc-learning-alerts"
}

variable "lambda_subscription_arn" {
  description = "ARN of the dpc-notify Lambda function subscribed to alert notifications."
  type        = string
  default     = null
}

variable "email_subscribers" {
  description = "Optional list of email recipients for alert notifications."
  type        = list(string)
  default     = []
}

variable "redshift_workgroup_name" {
  description = "Redshift Serverless workgroup monitored for capacity usage."
  type        = string
  default     = "dpc-learning"
}

variable "step_functions_alarm_threshold" {
  description = "Threshold for the number of Step Functions failures before raising an alarm."
  type        = number
  default     = 1
}

variable "redshift_rpu_threshold" {
  description = "Threshold for Redshift Serverless RPU utilization before raising an alarm."
  type        = number
  default     = 80
}
