# The audit bucket must stay private and encrypted with the account's managed S3 key.
run "audit_bucket_stays_private_and_encrypted" {
  command = plan

  variables {
    expected_account_id = "000000000000"
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.trail.block_public_acls,
      aws_s3_bucket_public_access_block.trail.block_public_policy,
      aws_s3_bucket_public_access_block.trail.ignore_public_acls,
      aws_s3_bucket_public_access_block.trail.restrict_public_buckets,
      one(one(aws_s3_bucket_server_side_encryption_configuration.trail.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256",
    ])
    error_message = "The audit trail bucket must block public access and use SSE-S3 encryption."
  }
}

# Budgets alert on ordinary recurring spend and cap the separately scoped Bedrock use.
run "account_spend_guards_remain_bounded" {
  command = plan

  variables {
    expected_account_id = "000000000000"
  }

  assert {
    condition = alltrue([
      aws_budgets_budget.account.limit_amount == "15",
      aws_budgets_budget.account.time_unit == "MONTHLY",
      aws_budgets_budget.bedrock_daily.limit_amount == "1",
      aws_budgets_budget.bedrock_daily.time_unit == "DAILY",
      aws_budgets_budget.bedrock_monthly.limit_amount == "10",
      aws_budgets_budget.bedrock_monthly.time_unit == "MONTHLY",
      one(aws_budgets_budget_action.bedrock_deny.action_threshold).action_threshold_type == "PERCENTAGE",
      one(aws_budgets_budget_action.bedrock_deny.action_threshold).action_threshold_value == 100,
    ])
    error_message = "Account and Bedrock budgets must keep their configured dollar and time limits."
  }
}
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

# Model the pre-existing imported objects without calling AWS or attempting import through a mock.
override_resource {
  target = aws_s3_bucket.trail
  values = { id = "neon1-audit-trail" }
}

override_resource {
  target = aws_s3_bucket_ownership_controls.trail
  values = { id = "neon1-audit-trail" }
}

override_resource {
  target = aws_s3_bucket_public_access_block.trail
  values = { id = "neon1-audit-trail" }
}

override_resource {
  target = aws_s3_bucket_versioning.trail
  values = { id = "neon1-audit-trail" }
}

override_resource {
  target = aws_s3_bucket_server_side_encryption_configuration.trail
  values = { id = "neon1-audit-trail" }
}

override_resource {
  target = aws_s3_bucket_object_lock_configuration.trail
  values = { id = "neon1-audit-trail" }
}

override_resource {
  target = aws_s3_bucket_lifecycle_configuration.trail
  values = { id = "neon1-audit-trail" }
}

override_resource {
  target = aws_s3_bucket_policy.trail
  values = { id = "neon1-audit-trail" }
}

override_resource {
  target = aws_cloudtrail.account
  values = { id = "neon1-account-trail" }
}

override_resource {
  target = aws_budgets_budget.account
  values = { id = "neon1-account" }
}

override_resource {
  target = aws_ce_anomaly_subscription.services
  values = { id = "neon1-anomaly-subscription" }
}
