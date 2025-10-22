locals {
  base_tags = merge({
    Project     = "dpc-learning",
    Environment = var.environment
  }, var.tags)
}

module "foundation" {
  source = "../modules/foundation"

  env  = var.environment
  tags = local.base_tags
}

module "secrets" {
  source = "../modules/secrets"

  env         = var.environment
  kms_key_arn = module.foundation.kms_key_arn
  tags        = local.base_tags
}

module "iam" {
  source = "../modules/iam"

  env         = var.environment
  bucket_arn  = module.foundation.data_bucket_arn
  bucket_name = module.foundation.data_bucket_name
  kms_key_arn = module.foundation.kms_key_arn
  tags        = local.base_tags
}
