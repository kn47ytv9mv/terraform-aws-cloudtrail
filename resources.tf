resource "random_uuid" "resource" {}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "logs" {
  bucket = "cloudtrail-${random_uuid.resource.id}"

  tags = var.tags
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id

  versioning_configuration {
    status = title(lower(var.versioning))
  }
}

resource "aws_s3_bucket_logging" "logs" {
  count = var.enable_access_logging ? 1 : 0

  bucket = aws_s3_bucket.logs.id

  target_bucket = var.access_log_bucket
  target_prefix = var.access_log_prefix != null ? var.access_log_prefix : ""
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_id != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_id
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.logs.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.logs.arn}/${var.s3_key_prefix != null ? "${var.s3_key_prefix}/" : ""}AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
      }
      ],
      var.is_organization_trail && var.organization_id != null ? [
        {
          Sid       = "AWSCloudTrailWriteOrg"
          Effect    = "Allow"
          Principal = { Service = "cloudtrail.amazonaws.com" }
          Action    = "s3:PutObject"
          Resource  = "${aws_s3_bucket.logs.arn}/${var.s3_key_prefix != null ? "${var.s3_key_prefix}/" : ""}AWSLogs/${var.organization_id}/*"
          Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
        }
    ] : [])
  })
}

data "aws_iam_policy_document" "cloudwatch_assume" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cloudwatch" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  assume_role_policy = data.aws_iam_policy_document.cloudwatch_assume[0].json

  tags = var.tags
}

resource "aws_iam_role_policy" "cloudwatch" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  role = aws_iam_role.cloudwatch[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${var.cloudwatch_logs_group_arn}:*"
    }]
  })
}

resource "aws_cloudtrail" "resource" {
  name           = coalesce(var.name, random_uuid.resource.id)
  s3_bucket_name = aws_s3_bucket.logs.id
  s3_key_prefix  = var.s3_key_prefix
  kms_key_id     = var.kms_key_id

  cloud_watch_logs_group_arn = var.enable_cloudwatch_logs ? "${var.cloudwatch_logs_group_arn}:*" : null
  cloud_watch_logs_role_arn  = try(aws_iam_role.cloudwatch[0].arn, null)

  is_multi_region_trail         = var.is_multi_region_trail
  is_organization_trail         = var.is_organization_trail
  include_global_service_events = var.include_global_service_events
  enable_log_file_validation    = var.enable_log_file_validation
  enable_logging                = var.enable_logging
  sns_topic_name                = var.sns_topic_name

  dynamic "event_selector" {
    for_each = var.event_selectors

    content {
      read_write_type           = event_selector.value.read_write_type
      include_management_events = event_selector.value.include_management_events

      dynamic "data_resource" {
        for_each = event_selector.value.data_resources

        content {
          type   = data_resource.value.type
          values = data_resource.value.values
        }
      }
    }
  }

  dynamic "insight_selector" {
    for_each = var.insight_selectors

    content {
      insight_type = insight_selector.value
    }
  }

  tags = var.tags

  depends_on = [aws_s3_bucket_policy.logs]
}

output "id" {
  description = "The name of the trail."
  value       = aws_cloudtrail.resource.id
}

output "arn" {
  description = "The ARN of the trail."
  value       = aws_cloudtrail.resource.arn
}

output "home_region" {
  description = "The region the trail was created in — where its own configuration lives, regardless of is_multi_region_trail."
  value       = aws_cloudtrail.resource.home_region
}

output "bucket" {
  description = "The name of the S3 bucket log files are delivered to."
  value       = aws_s3_bucket.logs.id
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket log files are delivered to."
  value       = aws_s3_bucket.logs.arn
}

output "cloudwatch_role_arn" {
  description = "The ARN of the IAM role created for CloudWatch Logs delivery, when enable_cloudwatch_logs is set. Null otherwise."
  value       = try(aws_iam_role.cloudwatch[0].arn, null)
}
