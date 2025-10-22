module "operations" {
  source = "../modules/operations"

  environment                    = var.environment
  alarm_name_prefix              = var.operations_alarm_name_prefix
  state_machine_arn              = var.operations_state_machine_arn
  alert_topic_arn                = var.operations_alert_topic_arn
  lambda_subscription_arn        = var.operations_lambda_subscription_arn
  email_subscribers              = var.operations_email_subscribers
  redshift_workgroup_name        = var.operations_redshift_workgroup_name
  step_functions_alarm_threshold = var.operations_step_functions_alarm_threshold
  redshift_rpu_threshold         = var.operations_redshift_rpu_threshold
  tags                           = var.default_tags
}
