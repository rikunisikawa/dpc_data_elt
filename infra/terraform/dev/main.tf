module "operations" {
  source = "../modules/operations"

  environment                     = var.environment
  state_machine_arn               = var.state_machine_arn
  alert_topic_arn                 = var.alert_topic_arn
  lambda_subscription_arn         = var.lambda_subscription_arn
  email_subscribers               = var.email_subscribers
  redshift_workgroup_name         = var.redshift_workgroup_name
  step_functions_alarm_threshold  = var.step_functions_alarm_threshold
  redshift_rpu_threshold          = var.redshift_rpu_threshold
  tags                            = {
    Project = "dpc-learning"
  }
}
