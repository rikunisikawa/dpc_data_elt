terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_iam_role" "redshift_copy" {
  name = var.copy_role_name
}

data "aws_kms_alias" "this" {
  name = var.kms_alias_name
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_subnet" "selected" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.key
}

locals {
  public_subnet_ids = [
    for subnet in data.aws_subnet.selected : subnet.id
    if subnet.map_public_ip_on_launch
  ]
}

resource "aws_security_group" "redshift_serverless" {
  name        = "${var.workgroup_name}-sg"
  description = "Redshift Serverless restricted ingress"
  vpc_id      = data.aws_vpc.default.id

  revoke_rules_on_delete = true

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.workgroup_name}-sg"
  })
}

module "redshift" {
  source = "./modules/redshift"

  workgroup_name             = var.workgroup_name
  namespace_name             = var.namespace_name
  database_name              = var.database_name
  base_capacity              = var.base_capacity
  snapshot_retention_period  = var.snapshot_retention_period
  subnet_ids                 = local.public_subnet_ids
  security_group_ids         = [aws_security_group.redshift_serverless.id]
  copy_role_arn              = data.aws_iam_role.redshift_copy.arn
  kms_key_arn                = data.aws_kms_alias.this.target_key_arn
  log_exports                = var.log_exports
  manage_admin_password      = var.manage_admin_password
  namespace_tags             = var.namespace_tags
  workgroup_tags             = var.workgroup_tags
}

output "redshift_namespace" {
  description = "Details of the Redshift Serverless namespace."
  value = {
    name     = module.redshift.namespace_name
    arn      = module.redshift.namespace_arn
    admin_db = var.database_name
  }
}

output "redshift_workgroup" {
  description = "Details of the Redshift Serverless workgroup."
  value = {
    name     = module.redshift.workgroup_name
    id       = module.redshift.workgroup_id
    endpoint = module.redshift.workgroup_endpoint
  }
}
