terraform {
  required_version = ">= 1.4.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

locals {
  alarm_prefix = length(trimspace(var.alarm_name_prefix)) > 0 ? trimspace(var.alarm_name_prefix) : "dpc-${var.environment}"
}

resource "aws_cloudwatch_metric_alarm" "step_functions_failed" {
  alarm_name          = "${local.alarm_prefix}-stepfunctions-failed"
  alarm_description   = "Alerts when Step Functions executions fail in the ${var.environment} environment."
  namespace           = "AWS/States"
  metric_name         = "ExecutionsFailed"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = var.step_functions_alarm_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    StateMachineArn = var.state_machine_arn
  }

  alarm_actions             = [var.alert_topic_arn]
  ok_actions                = [var.alert_topic_arn]
  insufficient_data_actions = []

  tags = merge(var.tags, {
    Component   = "operations"
    Environment = var.environment
  })
}

resource "aws_cloudwatch_metric_alarm" "redshift_rpu" {
  alarm_name          = "${local.alarm_prefix}-redshift-rpu-high"
  alarm_description   = "Alerts when Redshift Serverless RPU utilization remains above the defined threshold."
  namespace           = "AWS/RedshiftServerless"
  metric_name         = "RPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = var.redshift_rpu_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    WorkgroupName = var.redshift_workgroup_name
  }

  alarm_actions             = [var.alert_topic_arn]
  ok_actions                = [var.alert_topic_arn]
  insufficient_data_actions = []

  tags = merge(var.tags, {
    Component   = "operations"
    Environment = var.environment
  })
}

resource "aws_lambda_permission" "allow_sns" {
  count = var.lambda_subscription_arn == null ? 0 : 1

  statement_id  = "AllowExecutionFromSNS-${var.environment}"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_subscription_arn
  principal     = "sns.amazonaws.com"
  source_arn    = var.alert_topic_arn
}

resource "aws_sns_topic_subscription" "lambda" {
  count = var.lambda_subscription_arn == null ? 0 : 1

  topic_arn = var.alert_topic_arn
  protocol  = "lambda"
  endpoint  = var.lambda_subscription_arn

  depends_on = [aws_lambda_permission.allow_sns]
}

resource "aws_sns_topic_subscription" "email" {
  for_each = { for address in var.email_subscribers : address => address }

  topic_arn = var.alert_topic_arn
  protocol  = "email"
  endpoint  = each.value
}
