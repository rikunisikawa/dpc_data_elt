terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

locals {
  alarm_name_prefix = "dpc-${var.environment}"
  default_tags = merge(
    {
      Environment = var.environment
    },
    var.tags,
  )
}

resource "aws_lambda_permission" "allow_sns_notify" {
  statement_id  = "AllowExecutionFromSnsNotify"
  action        = "lambda:InvokeFunction"
  function_name = var.notify_lambda_arn
  principal     = "sns.amazonaws.com"
  source_arn    = var.sns_topic_arn
}

resource "aws_sns_topic_subscription" "notify_lambda" {
  topic_arn = var.sns_topic_arn
  protocol  = "lambda"
  endpoint  = var.notify_lambda_arn

  raw_message_delivery = var.sns_raw_message_delivery

  depends_on = [aws_lambda_permission.allow_sns_notify]
}

resource "aws_sns_topic_subscription" "email" {
  for_each = { for email in var.email_subscribers : email => email }

  topic_arn = var.sns_topic_arn
  protocol  = "email"
  endpoint  = each.value

  delivery_policy = var.email_delivery_policy
}

resource "aws_cloudwatch_metric_alarm" "step_functions_failed" {
  alarm_name          = "${local.alarm_name_prefix}-step-functions-failed"
  alarm_description   = "Alerts when the Step Functions state machine reports failed executions."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.step_functions_evaluation_periods
  datapoints_to_alarm = var.step_functions_datapoints_to_alarm
  threshold           = var.step_functions_failure_threshold
  treat_missing_data  = var.step_functions_treat_missing_data
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = var.step_functions_period_seconds
  statistic           = "Sum"

  dimensions = {
    StateMachineArn = var.state_machine_arn
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = var.send_ok_actions ? [var.sns_topic_arn] : []

  tags = local.default_tags
}

resource "aws_cloudwatch_metric_alarm" "redshift_rpu_utilization" {
  alarm_name          = "${local.alarm_name_prefix}-redshift-rpu-utilization"
  alarm_description   = "Alerts when Redshift Serverless RPU utilization remains above the configured threshold."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.redshift_rpu_evaluation_periods
  datapoints_to_alarm = var.redshift_rpu_datapoints_to_alarm
  threshold           = var.redshift_rpu_utilization_threshold
  treat_missing_data  = var.redshift_rpu_treat_missing_data
  metric_name         = "RPUUtilization"
  namespace           = "AWS/Redshift"
  period              = var.redshift_rpu_period_seconds
  statistic           = "Average"

  dimensions = {
    Workgroup = var.redshift_workgroup_name
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = var.send_ok_actions ? [var.sns_topic_arn] : []

  tags = local.default_tags
}
