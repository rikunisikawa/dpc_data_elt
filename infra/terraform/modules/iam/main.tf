data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

locals {
  logs_arn = "arn:${data.aws_partition.current.partition}:logs:*:${data.aws_caller_identity.current.account_id}:*"
  bucket_objects_arn = "${var.bucket_arn}/*"
}

# Lambda execution role
resource "aws_iam_role" "lambda" {
  name = "role-lambda-dpc"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, {
    Name = "role-lambda-dpc"
  })
}

resource "aws_iam_role_policy" "lambda_access" {
  name = "role-lambda-dpc-access"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLogging"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = local.logs_arn
      },
      {
        Sid    = "AllowS3ReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = local.bucket_objects_arn
      },
      {
        Sid    = "AllowListBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = var.bucket_arn
      },
      {
        Sid    = "AllowKmsUsage"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext"
        ]
        Resource = var.kms_key_arn
      },
      {
        Sid    = "AllowSecretsAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:dpc/*"
      },
      {
        Sid    = "AllowRedshiftDataApi"
        Effect = "Allow"
        Action = [
          "redshift-data:CancelStatement",
          "redshift-data:DescribeStatement",
          "redshift-data:ExecuteStatement",
          "redshift-data:GetStatementResult"
        ]
        Resource = "*"
      }
    ]
  })
}

# Step Functions role
resource "aws_iam_role" "stepfunctions" {
  name = "role-stepfunctions-dpc"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "states.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, {
    Name = "role-stepfunctions-dpc"
  })
}

resource "aws_iam_role_policy" "stepfunctions_access" {
  name = "role-stepfunctions-dpc-access"
  role = aws_iam_role.stepfunctions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaInvoke"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowSnsPublish"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowEventBridge"
        Effect = "Allow"
        Action = [
          "events:PutRule",
          "events:PutTargets",
          "events:DeleteRule",
          "events:RemoveTargets",
          "events:DescribeRule"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowLogDelivery"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:DescribeLogGroups",
          "logs:GetLogDelivery",
          "logs:ListLogDeliveries",
          "logs:UpdateLogDelivery"
        ]
        Resource = "*"
      }
    ]
  })
}

# Redshift COPY/UNLOAD role
resource "aws_iam_role" "redshift_copy" {
  name = "role-redshift-copy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "redshift.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, {
    Name = "role-redshift-copy"
  })
}

resource "aws_iam_role_policy" "redshift_copy_access" {
  name = "role-redshift-copy-access"
  role = aws_iam_role.redshift_copy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3Read"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          var.bucket_arn,
          local.bucket_objects_arn
        ]
      },
      {
        Sid    = "AllowKmsDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = var.kms_key_arn
      }
    ]
  })
}
