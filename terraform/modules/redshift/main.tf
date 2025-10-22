resource "aws_redshiftserverless_namespace" "this" {
  namespace_name            = var.namespace_name
  db_name                   = var.database_name
  default_iam_role_arn      = var.copy_role_arn
  iam_roles                 = [var.copy_role_arn]
  kms_key_id                = var.kms_key_arn
  log_exports               = var.log_exports
  manage_admin_password     = var.manage_admin_password
  snapshot_retention_period = var.snapshot_retention_period

  tags = merge(var.tags, var.namespace_tags)
}

resource "aws_redshiftserverless_workgroup" "this" {
  depends_on = [aws_redshiftserverless_namespace.this]

  workgroup_name        = var.workgroup_name
  namespace_name        = aws_redshiftserverless_namespace.this.namespace_name
  base_capacity         = var.base_capacity
  security_group_ids    = var.security_group_ids
  subnet_ids            = var.subnet_ids
  enhanced_vpc_routing  = true

  tags = merge(var.tags, var.workgroup_tags)
}
