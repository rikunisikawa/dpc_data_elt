data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  bucket_name = "dpc-learning-data-${var.env}"
  base_tags = merge(
    {
      Name = "dpc-learning-foundation-${var.env}"
    },
    var.tags
  )
}

resource "aws_kms_key" "dpc" {
  description             = "DPC learning platform CMK"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "Enable IAM User Permissions"
        Effect    = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })

  tags = merge(local.base_tags, {
    Name = "alias/dpc-learning-kms"
  })
}

resource "aws_kms_alias" "dpc" {
  name          = "alias/dpc-learning-kms"
  target_key_id = aws_kms_key.dpc.key_id
}

resource "aws_s3_bucket" "data" {
  bucket        = local.bucket_name
  force_destroy = false

  tags = merge(local.base_tags, {
    Name = local.bucket_name
  })
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.dpc.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AWSCloudTrailAclCheck"
        Effect   = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.data.arn
      },
      {
        Sid      = "AWSCloudTrailWrite"
        Effect   = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.data.arn}/logs/cloudtrail/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "dpc" {
  name                          = "dpc-learning-${var.env}"
  s3_bucket_name                = aws_s3_bucket.data.id
  s3_key_prefix                 = "logs/cloudtrail"
  kms_key_id                    = aws_kms_key.dpc.arn
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.data.arn}/raw/"]
    }
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail]

  tags = merge(local.base_tags, {
    Name = "dpc-learning-${var.env}-cloudtrail"
  })
}
