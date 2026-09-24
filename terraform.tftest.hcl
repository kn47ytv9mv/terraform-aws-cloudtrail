mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock-cloudtrail-cloudwatch-role"
    }
  }
}

run "default_config_creates_expected_resources" {
  command = apply

  assert {
    condition     = aws_cloudtrail.resource.is_multi_region_trail == true
    error_message = "is_multi_region_trail should default to true."
  }

  assert {
    condition     = aws_s3_bucket_versioning.logs.versioning_configuration[0].status == "Enabled"
    error_message = "versioning should default to enabled."
  }

  assert {
    condition     = aws_cloudtrail.resource.enable_log_file_validation == true
    error_message = "enable_log_file_validation should default to true."
  }

  assert {
    condition     = aws_cloudtrail.resource.is_organization_trail == false
    error_message = "is_organization_trail should default to false."
  }

  assert {
    condition     = length(aws_iam_role.cloudwatch) == 0
    error_message = "No cloudwatch_logs_group_arn given should create no IAM role."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.logs.block_public_acls == true
    error_message = "The log bucket should always have public access fully blocked."
  }
}

run "cloudwatch_logs_delivery_creates_role" {
  command = apply

  variables {
    enable_cloudwatch_logs    = true
    cloudwatch_logs_group_arn = "arn:aws:logs:us-east-1:123456789012:log-group:example"
  }

  assert {
    condition     = length(aws_iam_role.cloudwatch) == 1
    error_message = "cloudwatch_logs_group_arn should create exactly one IAM role."
  }

  assert {
    condition     = aws_cloudtrail.resource.cloud_watch_logs_group_arn == "arn:aws:logs:us-east-1:123456789012:log-group:example:*"
    error_message = "cloud_watch_logs_group_arn should append the :* log-stream wildcard AWS requires."
  }
}

run "organization_trail_adds_org_bucket_policy_statement" {
  command = apply

  variables {
    is_organization_trail = true
    organization_id       = "o-exampleorgid"
  }

  assert {
    condition     = length(regexall("AWSCloudTrailWriteOrg", aws_s3_bucket_policy.logs.policy)) == 1
    error_message = "is_organization_trail with organization_id set should add the org-scoped bucket policy statement."
  }
}

run "no_organization_id_omits_org_bucket_policy_statement" {
  command = apply

  assert {
    condition     = length(regexall("AWSCloudTrailWriteOrg", aws_s3_bucket_policy.logs.policy)) == 0
    error_message = "Without organization_id, the org-scoped bucket policy statement should not be added."
  }
}

run "event_selectors_render" {
  command = apply

  variables {
    event_selectors = [
      {
        read_write_type = "All"
        data_resources = [
          { type = "AWS::S3::Object", values = ["arn:aws:s3:::example-bucket/"] }
        ]
      }
    ]
  }

  assert {
    condition     = length(aws_cloudtrail.resource.event_selector) == 1
    error_message = "One event_selectors entry should render exactly one event_selector block."
  }
}

run "insight_selectors_render" {
  command = apply

  variables {
    insight_selectors = ["ApiCallRateInsight", "ApiErrorRateInsight"]
  }

  assert {
    condition     = length(aws_cloudtrail.resource.insight_selector) == 2
    error_message = "Two insight_selectors entries should render exactly two insight_selector blocks."
  }
}

run "access_log_bucket_enables_bucket_logging" {
  command = apply

  variables {
    enable_access_logging = true
    access_log_bucket     = "example-access-logs-bucket"
    access_log_prefix     = "cloudtrail-bucket/"
  }

  assert {
    condition     = length(aws_s3_bucket_logging.logs) == 1
    error_message = "access_log_bucket given should create exactly one aws_s3_bucket_logging resource."
  }

  assert {
    condition     = aws_s3_bucket_logging.logs[0].target_bucket == "example-access-logs-bucket"
    error_message = "access_log_bucket should pass through unchanged."
  }
}

run "access_log_bucket_without_prefix_defaults_to_empty_string" {
  command = apply

  variables {
    enable_access_logging = true
    access_log_bucket     = "example-access-logs-bucket"
  }

  assert {
    condition     = aws_s3_bucket_logging.logs[0].target_prefix == ""
    error_message = "access_log_prefix left unset should default target_prefix to an empty string, not error."
  }
}

run "no_access_log_bucket_disables_bucket_logging" {
  command = apply

  assert {
    condition     = length(aws_s3_bucket_logging.logs) == 0
    error_message = "No access_log_bucket given should create no aws_s3_bucket_logging resource."
  }
}

run "kms_key_id_encrypts_bucket_with_sse_kms" {
  command = apply

  variables {
    kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/abcd1234-ab12-cd34-ef56-abcdef123456"
  }

  assert {
    condition     = anytrue([for r in aws_s3_bucket_server_side_encryption_configuration.logs.rule : anytrue([for d in r.apply_server_side_encryption_by_default : d.sse_algorithm == "aws:kms"])])
    error_message = "kms_key_id given should switch the bucket's own encryption to SSE-KMS."
  }
}

run "no_kms_key_id_uses_sse_s3" {
  command = apply

  assert {
    condition     = anytrue([for r in aws_s3_bucket_server_side_encryption_configuration.logs.rule : anytrue([for d in r.apply_server_side_encryption_by_default : d.sse_algorithm == "AES256"])])
    error_message = "No kms_key_id given should default the bucket's own encryption to SSE-S3 (AES256)."
  }
}

run "readme_default_example" {
  command = plan
}

run "readme_organization_example" {
  command = plan

  variables {
    is_organization_trail     = true
    organization_id           = "o-exampleorgid"
    enable_cloudwatch_logs    = true
    cloudwatch_logs_group_arn = "arn:aws:logs:us-east-1:123456789012:log-group:org-trail"
  }
}

run "enable_access_logging_without_access_log_bucket_is_rejected" {
  command = plan

  variables {
    enable_access_logging = true
  }

  expect_failures = [var.enable_access_logging]
}

run "access_log_bucket_without_enable_access_logging_is_rejected" {
  command = plan

  variables {
    access_log_bucket = "example-access-logs-bucket"
  }

  expect_failures = [var.enable_access_logging]
}

run "enable_cloudwatch_logs_without_cloudwatch_logs_group_arn_is_rejected" {
  command = plan

  variables {
    enable_cloudwatch_logs = true
  }

  expect_failures = [var.enable_cloudwatch_logs]
}

run "cloudwatch_logs_group_arn_without_enable_cloudwatch_logs_is_rejected" {
  command = plan

  variables {
    cloudwatch_logs_group_arn = "arn:aws:logs:us-east-1:123456789012:log-group:example"
  }

  expect_failures = [var.enable_cloudwatch_logs]
}
