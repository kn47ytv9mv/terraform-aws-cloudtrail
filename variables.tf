variable "name" {
  default     = null
  description = "Name of the trail. If null, a unique name is generated."
}

variable "s3_key_prefix" {
  default     = null
  description = "Prefix for log file object keys in the log bucket, before the AWSLogs/<account-id>/ path AWS adds automatically."
}

variable "enable_access_logging" {
  default     = false
  description = "Whether the trail's own S3 bucket delivers server access logs to access_log_bucket. This is a separate switch because Terraform requires the decision to be known before it plans, and a target bucket created in the same configuration is not — see the Design section."

  validation {
    condition     = !var.enable_access_logging || var.access_log_bucket != null
    error_message = "enable_access_logging requires access_log_bucket to name the bucket receiving the logs."
  }

  validation {
    condition     = var.access_log_bucket == null || var.enable_access_logging
    error_message = "access_log_bucket is set but enable_access_logging is false, so no logs would be delivered. Set enable_access_logging = true."
  }
}

variable "access_log_bucket" {
  default     = null
  description = "Name of a separate S3 bucket to send this module's own log bucket's server access logs to — a record of who accessed the audit trail itself, a CIS-recommended control for a CloudTrail bucket specifically. If null, access logging is disabled."
}

variable "access_log_prefix" {
  default     = null
  description = "Prefix for access log object keys in access_log_bucket. Only used when access_log_bucket is set."
}

variable "kms_key_id" {
  default     = null
  description = "ARN of a KMS key to encrypt delivered log files with, and to use for the log bucket's own SSE-KMS encryption. If null, the bucket uses SSE-S3 and log files are unencrypted at the trail level (still encrypted at rest by S3 either way)."
}

variable "versioning" {
  default     = "enabled"
  description = "Versioning state of the log bucket (e.g. 'enabled', 'suspended', or 'disabled'). Defaults enabled, so a delivered log file cannot be silently overwritten or lost."
}

variable "enable_cloudwatch_logs" {
  default     = false
  description = "Whether the trail also delivers events to CloudWatch Logs, creating the IAM role that permits it. This is a separate switch because Terraform requires the decision to be known before it plans, and the ARN of a log group created in the same configuration is not — see the Design section."

  validation {
    condition     = !var.enable_cloudwatch_logs || var.cloudwatch_logs_group_arn != null
    error_message = "enable_cloudwatch_logs requires cloudwatch_logs_group_arn to name the destination log group."
  }

  validation {
    condition     = var.cloudwatch_logs_group_arn == null || var.enable_cloudwatch_logs
    error_message = "cloudwatch_logs_group_arn is set but enable_cloudwatch_logs is false, so no events would be delivered. Set enable_cloudwatch_logs = true."
  }
}

variable "cloudwatch_logs_group_arn" {
  default     = null
  description = "ARN of a CloudWatch Logs group (e.g. from terraform-aws-cloudwatch-log-group) to also deliver events to, for near-real-time monitoring/alerting instead of only the S3 log bucket's batch delivery. This module creates its own tightly-scoped IAM role for CloudTrail to write into it — no separate role to pass in."
}

variable "is_multi_region_trail" {
  default     = true
  description = "Whether the trail logs events from every region, not just this provider's own. Defaults true — a single-region trail misses activity everywhere else, which defeats the purpose of an audit trail for most accounts."
}

variable "is_organization_trail" {
  default     = false
  description = "Whether this trail also logs events for every account in the AWS Organization, not just this one. Only valid in the organization's management account. Pair with organization_id so the log bucket's policy can scope write access to every member account's log path, not just this account's."
}

variable "organization_id" {
  default     = null
  description = "The AWS Organization's ID (e.g. 'o-xxxxxxxxxx'), only used when is_organization_trail is true — scopes the log bucket's policy to also allow member accounts' log deliveries. Leave null for a non-organization trail."
}

variable "include_global_service_events" {
  default     = true
  description = "Whether events from global services (IAM, CloudFront, Route53, and so on) are included, in addition to this trail's own region(s)."
}

variable "enable_log_file_validation" {
  default     = true
  description = "Whether CloudTrail generates a digest file for each delivered log file, letting its integrity be verified after the fact — detects if a log file was altered or deleted. Defaults true, since an audit trail that cannot prove its own integrity is a materially weaker one."
}

variable "enable_logging" {
  default     = true
  description = "Whether the trail is actively logging. Set false to pause logging without destroying the trail."
}

variable "event_selectors" {
  default     = []
  description = "Which events the trail logs, beyond the default of all management events. Each entry sets read_write_type ('ReadOnly', 'WriteOnly', or 'All'), whether management events are included at all, and optionally data_resources (e.g. type 'AWS::S3::Object' with values listing bucket ARNs, to also log object-level S3 activity) for the data-event volume this trail should actually pay to log — data events are not included by default, since they can be high-volume and directly drive cost."
  type = list(object({
    read_write_type           = optional(string, "All")
    include_management_events = optional(bool, true)
    data_resources = optional(list(object({
      type   = string
      values = list(string)
    })), [])
  }))
}

variable "insight_selectors" {
  default     = []
  description = "CloudTrail Insights types to enable (e.g. 'ApiCallRateInsight', 'ApiErrorRateInsight') — anomaly detection on unusual API activity volume or error rates. Bills separately per analyzed event; not enabled by default for that reason."
}

variable "sns_topic_name" {
  default     = null
  description = "Name (not ARN) of an SNS topic to notify every time a new log file is delivered to the bucket. If null, no notification is sent."
}

variable "tags" {
  default     = null
  description = "A map of tags to assign to the trail and its log bucket."
}
