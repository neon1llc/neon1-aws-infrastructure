# account/main.tf - Account-wide guardrails no app stack owns: the audit trail of every change in every
# region, an account-wide budget, and the cost anomaly email. Created by hand on 2026-11-16 and taken
# over here with import blocks, so the first plan should show only tag changes.


locals {
  account     = var.expected_account_id
  trail_name  = "neon1-account-trail"
  bucket_name = "neon1-audit-trail"
  trail_arn   = "arn:aws:cloudtrail:us-east-1:${local.account}:trail/${local.trail_name}"
}


# --- Take over what was created by hand ---


import {
  to = aws_s3_bucket.trail
  id = "neon1-audit-trail"
}

import {
  to = aws_s3_bucket_ownership_controls.trail
  id = "neon1-audit-trail"
}

import {
  to = aws_s3_bucket_public_access_block.trail
  id = "neon1-audit-trail"
}

import {
  to = aws_s3_bucket_versioning.trail
  id = "neon1-audit-trail"
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.trail
  id = "neon1-audit-trail"
}

import {
  to = aws_s3_bucket_object_lock_configuration.trail
  id = "neon1-audit-trail"
}

import {
  to = aws_s3_bucket_lifecycle_configuration.trail
  id = "neon1-audit-trail"
}

import {
  to = aws_s3_bucket_policy.trail
  id = "neon1-audit-trail"
}

import {
  to = aws_cloudtrail.account
  id = local.trail_arn
}

import {
  to = aws_budgets_budget.account
  id = "${local.account}:neon1-account"
}

# AWS made this monitor and subscription when cost anomaly detection was first opened (2025-08-13)
import {
  to = aws_ce_anomaly_subscription.services
  id = "arn:aws:ce::${local.account}:anomalysubscription/a2427116-e69f-4bb0-bd8d-7cb62921f1eb"
}


# --- Audit trail bucket: private, encrypted, and every file locked for a year ---


resource "aws_s3_bucket" "trail" {
  bucket = local.bucket_name

  # Object Lock can only be switched on when a bucket is created
  object_lock_enabled = true

  # Audit history outlives infrastructure changes; never delete it implicitly
  force_destroy = false
}


# No ACLs; the account owns every object CloudTrail writes
resource "aws_s3_bucket_ownership_controls" "trail" {
  bucket = aws_s3_bucket.trail.id
  rule { object_ownership = "BucketOwnerEnforced" }
}


resource "aws_s3_bucket_public_access_block" "trail" {
  bucket                  = aws_s3_bucket.trail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


# Object Lock needs versioning; it was switched on with the lock
resource "aws_s3_bucket_versioning" "trail" {
  bucket = aws_s3_bucket.trail.id
  versioning_configuration { status = "Enabled" }
}


# S3-managed keys: no KMS key to pay for or lose
resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
    bucket_key_enabled = true
  }
}


# Governance mode: nobody deletes a log file for a year unless an admin deliberately bypasses the lock
resource "aws_s3_bucket_object_lock_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = var.trail_lock_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.trail]
}


# Files expire after the lock plus a margin, so the bucket stays a few cents a month
resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    id     = "expire-after-400-days"
    status = "Enabled"
    filter {}

    expiration { days = var.trail_days }
    noncurrent_version_expiration { noncurrent_days = 30 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }

  depends_on = [aws_s3_bucket_versioning.trail]
}


# Only this account's trail may write, only under AWSLogs/<account>/, and only over HTTPS
resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "CloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.trail.arn
        Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn } }
      },
      {
        Sid       = "CloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.trail.arn}/AWSLogs/${local.account}/*"
        Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn, "s3:x-amz-acl" = "bucket-owner-full-control" } }
      },
      {
        Sid       = "HttpsOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.trail.arn, "${aws_s3_bucket.trail.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })
}


# --- The trail: every management event in every region, with tamper-evident digest files ---


# The first copy of management events is free; no data events, no CloudWatch Logs, so the cost is storage.
# S3-managed encryption, not a customer key: a KMS key costs more than the whole trail (same reason as AWS-0132)
#trivy:ignore:AWS-0015
resource "aws_cloudtrail" "account" {
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.trail.id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  enable_logging                = true

  depends_on = [aws_s3_bucket_policy.trail]
}


# --- Spending: one line for the whole account, tagged or not ---


# The app stacks budget their own tagged resources; this catches everything else too
resource "aws_budgets_budget" "account" {
  name         = "neon1-account"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Recurring spend only: one-time fees have their own budget below
  cost_filter {
    name   = "CostCategory"
    values = ["${aws_ce_cost_category.run_rate.name}$ongoing"]
  }

  # Tax on recurring spend recurs with it
  cost_types {
    include_tax = true
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.alert_emails
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.alert_emails
  }
}


# AWS's default service monitor emailed only at $100 and 40% together, which this account never reaches
resource "aws_ce_anomaly_subscription" "services" {
  name             = "Default-Services-Subscription"
  frequency        = "DAILY"
  monitor_arn_list = ["arn:aws:ce::${local.account}:anomalymonitor/c34a3689-6e7e-405b-98b1-cd3c275e0cfe"]

  dynamic "subscriber" {
    for_each = var.alert_emails
    content {
      type    = "EMAIL"
      address = subscriber.value
    }
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.anomaly_threshold_usd)]
    }
  }
}


# Splits the bill so one-time fees never count against the recurring budget. One-time means domain
# registration, renewal, and transfer, plus upfront purchases. Everything else recurs, including metered
# model calls and new kinds of charges nobody has sorted yet
resource "aws_ce_cost_category" "run_rate" {
  name          = "neon1-run-rate"
  rule_version  = "CostCategoryExpression.v1"
  default_value = "ongoing"

  rule {
    type  = "REGULAR"
    value = "one_time"
    rule {
      dimension {
        key           = "SERVICE_CODE"
        values        = ["AmazonRegistrar"]
        match_options = ["EQUALS"]
      }
    }
  }

  rule {
    type  = "REGULAR"
    value = "one_time"
    rule {
      dimension {
        key           = "USAGE_TYPE"
        values        = ["Route53-Domains"]
        match_options = ["ENDS_WITH"]
      }
    }
  }

  rule {
    type  = "REGULAR"
    value = "one_time"
    rule {
      dimension {
        key           = "RECORD_TYPE"
        values        = ["Fee", "SavingsPlanUpfrontFee"]
        match_options = ["EQUALS"]
      }
    }
  }
}


# Keeps one-time fees visible: an email in any month they pass a dollar, outside the recurring budget
resource "aws_budgets_budget" "one_time" {
  name         = "neon1-one-time"
  budget_type  = "COST"
  limit_amount = "1"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "CostCategory"
    values = ["${aws_ce_cost_category.run_rate.name}$one_time"]
  }

  cost_types {
    include_tax = true
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.alert_emails
  }
}
