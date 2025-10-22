terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

locals {
  lambda_functions = {
    for name, cfg in var.lambda_functions : name => {
      function_name = try(trimspace(cfg.function_name), "") != "" ? cfg.function_name : "dpc-${replace(name, "_", "-")}"
      description   = try(trimspace(cfg.description), "") != "" ? cfg.description : "DPC pipeline ${replace(name, "_", " ")} function"
      handler       = cfg.handler
      runtime       = cfg.runtime
      package_key   = cfg.package_key
      source_code_hash = try(cfg.source_code_hash, null)
      timeout       = try(cfg.timeout, null) != null ? cfg.timeout : var.lambda_default_timeout
      memory_size   = try(cfg.memory_size, null) != null ? cfg.memory_size : var.lambda_default_memory_size
      environment   = merge(
        var.lambda_environment_defaults,
        try(cfg.environment, {}),
        name == "notify" && var.notify_slack_secret_arn != "" ? { SLACK_WEBHOOK_SECRET_ARN = var.notify_slack_secret_arn } : {},
        name == "compute_readmit" && var.redshift_secret_arn != "" ? { REDSHIFT_SECRET_ARN = var.redshift_secret_arn } : {},
        name == "export_parquet" && var.export_parquet_target_bucket != "" ? { TARGET_BUCKET = var.export_parquet_target_bucket } : {}
      )
    }
  }

  dbt_environment_base = merge(
    var.dbt_environment_defaults,
    var.redshift_secret_arn != "" ? { REDSHIFT_SECRET_ARN = var.redshift_secret_arn } : {},
    var.dbt_environment_overrides
  )

  dbt_environment_pairs = [
    for k, v in local.dbt_environment_base : {
      Name  = k
      Value = v
    }
  ]

  dbt_container_definition = merge({
    name      = var.dbt_container_name
    image     = var.dbt_container_image != "" ? var.dbt_container_image : "${aws_ecr_repository.dbt.repository_url}:latest"
    essential = true
    command   = var.dbt_container_command
    environment = [
      for k, v in local.dbt_environment_base : {
        name  = k
        value = v
      }
    ]
  }, var.dbt_log_configuration != null ? { logConfiguration = var.dbt_log_configuration } : {})

  dbt_state_machine_environment_overrides = [
    for item in var.dbt_state_machine_environment :
    merge(
      { Name = item.name },
      try(item.value, null) != null ? { Value = item.value } : {},
      try(item.value_path, null) != null ? { "Value.$" = item.value_path } : {}
    )
  ]
}

resource "aws_lambda_function" "pipeline" {
  for_each = local.lambda_functions

  function_name = each.value.function_name
  role          = var.lambda_role_arn
  description   = each.value.description
  handler       = each.value.handler
  runtime       = each.value.runtime
  s3_bucket     = var.lambda_package_bucket
  s3_key        = each.value.package_key
  timeout       = each.value.timeout
  memory_size   = each.value.memory_size
  publish       = var.lambda_publish
  tags          = var.tags

  environment {
    variables = each.value.environment
  }

  layers         = var.lambda_layers
  source_code_hash = try(each.value.source_code_hash, null)

}

resource "aws_sns_topic" "pipeline" {
  name = var.sns_topic_name
  tags = var.tags
}

resource "aws_lambda_permission" "allow_sns_notify" {
  statement_id  = "AllowExecutionFromSnsNotify"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pipeline["notify"].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.pipeline.arn
}

resource "aws_sns_topic_subscription" "notify" {
  topic_arn = aws_sns_topic.pipeline.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.pipeline["notify"].arn

  raw_message_delivery = var.sns_subscription_raw_message_delivery

  depends_on = [aws_lambda_permission.allow_sns_notify]
}

resource "aws_ecr_repository" "dbt" {
  name                 = var.dbt_repository_name
  force_delete         = var.dbt_repository_force_delete
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

resource "aws_ecs_task_definition" "dbt" {
  family                   = var.dbt_task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.dbt_task_cpu)
  memory                   = tostring(var.dbt_task_memory)
  execution_role_arn       = var.dbt_execution_role_arn
  task_role_arn            = var.dbt_task_role_arn
  container_definitions    = jsonencode([local.dbt_container_definition])
  tags                     = var.tags
}

locals {
  lambda_arns = { for name, fn in aws_lambda_function.pipeline : name => fn.arn }

  dbt_container_override_environment = concat(
    local.dbt_environment_pairs,
    local.dbt_state_machine_environment_overrides
  )

  state_machine_definition = jsonencode({
    Comment = var.state_machine_comment
    StartAt = "ValidateManifest"
    States = {
      ValidateManifest = {
        Type       = "Task"
        Resource   = "arn:aws:states:::lambda:invoke"
        ResultPath = "$.validate_manifest"
        Parameters = {
          FunctionName = local.lambda_arns.validate_manifest
          "Payload.$"  = "$"
        }
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error"
            Next        = "NotifyFailure"
          }
        ]
        Next = "CopyRaw"
      }

      CopyRaw = {
        Type       = "Task"
        Resource   = "arn:aws:states:::lambda:invoke"
        ResultPath = "$.copy_raw"
        Parameters = {
          FunctionName = local.lambda_arns.copy_raw
          "Payload.$"  = "$"
        }
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error"
            Next        = "RollbackStage"
          }
        ]
        Next = "ComputeReadmit"
      }

      ComputeReadmit = {
        Type       = "Task"
        Resource   = "arn:aws:states:::lambda:invoke"
        ResultPath = "$.compute_readmit"
        Parameters = {
          FunctionName = local.lambda_arns.compute_readmit
          "Payload.$"  = "$"
        }
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error"
            Next        = "RollbackStage"
          }
        ]
        Next = "RunDbtTransformations"
      }

      RunDbtTransformations = {
        Type       = "Task"
        Resource   = "arn:aws:states:::ecs:runTask.sync"
        ResultPath = "$.dbt"
        Parameters = {
          LaunchType     = "FARGATE"
          Cluster        = var.ecs_cluster_arn
          TaskDefinition = aws_ecs_task_definition.dbt.arn
          NetworkConfiguration = {
            AwsvpcConfiguration = {
              Subnets        = var.ecs_subnet_ids
              SecurityGroups = var.ecs_security_group_ids
              AssignPublicIp = var.ecs_assign_public_ip ? "ENABLED" : "DISABLED"
            }
          }
          Overrides = {
            ContainerOverrides = [
              {
                Name      = var.dbt_container_name
                Command   = var.dbt_state_machine_command
                Environment = local.dbt_container_override_environment
              }
            ]
          }
        }
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error"
            Next        = "RollbackStage"
          }
        ]
        Next = "ExportParquet"
      }

      ExportParquet = {
        Type       = "Task"
        Resource   = "arn:aws:states:::lambda:invoke"
        ResultPath = "$.export_parquet"
        Parameters = {
          FunctionName = local.lambda_arns.export_parquet
          "Payload.$"  = "$"
        }
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error"
            Next        = "NotifyFailure"
          }
        ]
        Next = "NotifySuccess"
      }

      RollbackStage = {
        Type       = "Pass"
        ResultPath = "$.rollback"
        Result = {
          truncate_enabled = var.enable_rollback_truncate
          statements       = var.rollback_statements
        }
        Next = "NotifyFailure"
      }

      NotifySuccess = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = local.lambda_arns.notify
          Payload = {
            status   = "SUCCESS"
            "detail.$" = "$"
          }
        }
        End = true
      }

      NotifyFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = local.lambda_arns.notify
          Payload = {
            status   = "FAILURE"
            "detail.$" = "$"
          }
        }
        End = true
      }
    }
  })
}

resource "aws_sfn_state_machine" "pipeline" {
  name       = var.state_machine_name
  role_arn   = var.state_machine_role_arn
  definition = local.state_machine_definition
  tags       = var.tags
}

resource "aws_cloudwatch_event_rule" "pipeline" {
  name                = "${var.state_machine_name}-schedule"
  schedule_expression = var.eventbridge_schedule_expression
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "pipeline" {
  rule      = aws_cloudwatch_event_rule.pipeline.name
  target_id = "${var.state_machine_name}-trigger"
  arn       = aws_sfn_state_machine.pipeline.arn
  role_arn  = var.eventbridge_role_arn
  input     = jsonencode(var.eventbridge_input)
}

resource "aws_iam_policy" "manual_start" {
  name        = var.manual_start_policy_name
  description = "Allows operators to manually start and inspect the DPC pipeline state machine."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "states:DescribeStateMachine",
          "states:ListExecutions",
          "states:StartExecution"
        ]
        Resource = aws_sfn_state_machine.pipeline.arn
      }
    ]
  })
}
