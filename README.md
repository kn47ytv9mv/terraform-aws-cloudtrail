# terraform-aws-cloudtrail

Terraform module for a CloudTrail trail — a durable, tamper-evident
record of every API call made against this account (or, as an
organization trail, every account in the organization), independent of
any application-level logging.

## Cost

CloudTrail's management-event logging is free; this module's real
charges are the S3 bucket it creates for log storage (billed for
storage consumed, standard S3 rates) and, if `event_selectors` enables
data events, a per-100,000-events charge for the data-event volume
logged. `insight_selectors` bills per analyzed management event.
`cloudwatch_logs_group_arn` adds standard CloudWatch Logs ingestion and
storage charges on top. See AWS's
[CloudTrail pricing](https://aws.amazon.com/cloudtrail/pricing/) page
for current rates.

## Design

This module creates its own dedicated S3 bucket for log delivery,
rather than taking an existing bucket — a CloudTrail log bucket needs
a specific bucket policy (`AWSCloudTrailAclCheck`/`AWSCloudTrailWrite`)
that has no reuse value for any other purpose, the same reasoning
`terraform-aws-vpc` uses for its own inline flow-log IAM role. The
bucket always has public access fully blocked; encryption follows
`kms_key_id` (SSE-KMS if set, SSE-S3 otherwise). Set `access_log_bucket`
to record who accesses the audit trail itself — server access logging
on this module's own log bucket, a CIS-recommended control specific to
a CloudTrail bucket that Trivy flags directly if left unset.

Scales from the simplest case to an organization-wide one without
changing shape: leave every optional variable at its default for a
single-account, all-regions, management-events-only trail (this
module's own default, and a reasonable one for most accounts); add
`cloudwatch_logs_group_arn` for near-real-time delivery alongside the
batched S3 delivery; add `event_selectors` to also log data-plane
activity (S3 object-level access, Lambda invocations) at the cost of
higher event volume; set `is_organization_trail` (with
`organization_id`, so the bucket policy can admit every member
account's log path) to cover the whole organization from one trail in
the management account.

`event_selectors` models AWS's simpler, classic event-selector shape
rather than the newer field-based `advanced_event_selector` — covers
the overwhelming majority of real "also log data events for these
buckets/functions" needs without the added complexity of arbitrary
field-match conditions; reach for the raw resource directly if a
specific advanced filter is genuinely required.

### Switches that look redundant, and are not

`enable_access_logging` alongside `access_log_bucket`, and
`enable_cloudwatch_logs` alongside `cloudwatch_logs_group_arn`, read like a switch
you should not have to remember. It exists because **Terraform decides
how many resources to create before it knows any value AWS computes.**
Gating on `access_log_bucket != null` works only while the bucket name is
written literally in the configuration; point it at a bucket created in
the same apply and the plan fails outright with *"Invalid count argument
... cannot be determined until apply"*, because Terraform cannot yet tell
whether that name is null.

A boolean the caller writes is always known at plan time, so the gate
holds no matter where the bucket name comes from. Supplying one without
the other is rejected rather than silently ignored, in both directions.

## Usage

```hcl
module "cloudtrail" {
  source = "kn47ytv9mv/cloudtrail/aws"
}
```

Or directly from this repository, an organization trail with
CloudWatch Logs delivery and S3 data-event logging:

```hcl
module "cloudtrail" {
  source = "github.com/kn47ytv9mv/terraform-aws-cloudtrail"

  is_organization_trail     = true
  organization_id           = "o-exampleorgid"
  enable_cloudwatch_logs    = true
  cloudwatch_logs_group_arn = module.cloudtrail_log_group.arn

  event_selectors = [
    {
      read_write_type = "All"
      data_resources = [
        { type = "AWS::S3::Object", values = ["${module.bucket.arn}/"] }
      ]
    }
  ]

  insight_selectors = ["ApiCallRateInsight", "ApiErrorRateInsight"]
}
```

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.9 |
| aws | ~> 6.61 |
| random | ~> 3.9 |

## Providers

| Name | Version |
|---|---|
| aws | ~> 6.61 |
| random | ~> 3.9 |

## Inputs

| Name | Description | Default | Required |
|---|---|---|---|
| name | Name of the trail. If null, a unique name is generated. | `null` | no |
| s3_key_prefix | Prefix for log file object keys in the log bucket, before the AWSLogs/<account-id>/ path AWS adds automatically. | `null` | no |
| enable_access_logging | Whether this module's own log bucket delivers server access logs to `access_log_bucket`. Separate from the bucket name because Terraform needs the decision known at plan time — see Design. | `false` | no |
| access_log_bucket | Requires `enable_access_logging`. Name of a separate S3 bucket to send this module's own log bucket's server access logs to — a record of who accessed the audit trail itself, a CIS-recommended control for a CloudTrail bucket specifically. If null, access logging is disabled. | `null` | no |
| access_log_prefix | Prefix for access log object keys in access_log_bucket. Only used when access_log_bucket is set. | `null` | no |
| versioning | Versioning state of the log bucket (e.g. 'enabled', 'suspended', or 'disabled'). Defaults enabled, so a delivered log file cannot be silently overwritten or lost. | `"enabled"` | no |
| kms_key_id | ARN of a KMS key to encrypt delivered log files with, and to use for the log bucket's own SSE-KMS encryption. If null, the bucket uses SSE-S3 and log files are unencrypted at the trail level (still encrypted at rest by S3 either way). | `null` | no |
| enable_cloudwatch_logs | Whether the trail also delivers events to CloudWatch Logs, creating the IAM role that permits it. Separate from the ARN because Terraform needs the decision known at plan time — see Design. | `false` | no |
| cloudwatch_logs_group_arn | Requires `enable_cloudwatch_logs`. ARN of a CloudWatch Logs group (e.g. from terraform-aws-cloudwatch-log-group) to also deliver events to, for near-real-time monitoring/alerting instead of only the S3 log bucket's batch delivery. This module creates its own tightly-scoped IAM role for CloudTrail to write into it — no separate role to pass in. | `null` | no |
| is_multi_region_trail | Whether the trail logs events from every region, not just this provider's own. Defaults true — a single-region trail misses activity everywhere else, which defeats the purpose of an audit trail for most accounts. | `true` | no |
| is_organization_trail | Whether this trail also logs events for every account in the AWS Organization, not just this one. Only valid in the organization's management account. Pair with organization_id so the log bucket's policy can scope write access to every member account's log path, not just this account's. | `false` | no |
| organization_id | The AWS Organization's ID (e.g. 'o-xxxxxxxxxx'), only used when is_organization_trail is true — scopes the log bucket's policy to also allow member accounts' log deliveries. Leave null for a non-organization trail. | `null` | no |
| include_global_service_events | Whether events from global services (IAM, CloudFront, Route53, and so on) are included, in addition to this trail's own region(s). | `true` | no |
| enable_log_file_validation | Whether CloudTrail generates a digest file for each delivered log file, letting its integrity be verified after the fact — detects if a log file was altered or deleted. Defaults true, since an audit trail that cannot prove its own integrity is a materially weaker one. | `true` | no |
| enable_logging | Whether the trail is actively logging. Set false to pause logging without destroying the trail. | `true` | no |
| event_selectors | Which events the trail logs, beyond the default of all management events. Each entry sets read_write_type ('ReadOnly', 'WriteOnly', or 'All'), whether management events are included at all, and optionally data_resources (e.g. type 'AWS::S3::Object' with values listing bucket ARNs, to also log object-level S3 activity) for the data-event volume this trail should actually pay to log — data events are not included by default, since they can be high-volume and directly drive cost. | `[]` | no |
| insight_selectors | CloudTrail Insights types to enable (e.g. 'ApiCallRateInsight', 'ApiErrorRateInsight') — anomaly detection on unusual API activity volume or error rates. Bills separately per analyzed event; not enabled by default for that reason. | `[]` | no |
| sns_topic_name | Name (not ARN) of an SNS topic to notify every time a new log file is delivered to the bucket. If null, no notification is sent. | `null` | no |
| tags | A map of tags to assign to the trail and its log bucket. | `null` | no |

## Outputs

| Name | Description |
|---|---|
| id | The name of the trail. |
| arn | The ARN of the trail. |
| home_region | The region the trail was created in — where its own configuration lives, regardless of is_multi_region_trail. |
| bucket | The name of the S3 bucket log files are delivered to. |
| bucket_arn | The ARN of the S3 bucket log files are delivered to. |
| cloudwatch_role_arn | The ARN of the IAM role created for CloudWatch Logs delivery, when `enable_cloudwatch_logs` is set. Null otherwise. |

## License

MIT — see [LICENSE.md](LICENSE.md).
