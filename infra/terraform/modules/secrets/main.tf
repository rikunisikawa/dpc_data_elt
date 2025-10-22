locals {
  secrets = {
    redshift_credentials = {
      name        = "dpc/redshift/credentials"
      description = "Redshift Data API credentials placeholder (${var.env})"
    }
    notifications_slack = {
      name        = "dpc/notifications/slack"
      description = "Slack webhook placeholder for DPC notifications (${var.env})"
    }
  }
}

resource "aws_secretsmanager_secret" "this" {
  for_each = local.secrets

  name        = each.value.name
  description = each.value.description
  kms_key_id  = var.kms_key_arn

  tags = merge(var.tags, {
    Name = each.value.name
  })
}

resource "aws_secretsmanager_secret_version" "placeholder" {
  for_each = aws_secretsmanager_secret.this

  secret_id     = each.value.id
  secret_string = jsonencode({})
}
