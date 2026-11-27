mock_provider "aws" {
  mock_data "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:us-east-1:000000000000:certificate/00000000-0000-0000-0000-000000000000"
    }
  }

  mock_data "aws_cognito_user_pools" {
    defaults = {
      ids = ["us-east-1_MockPool"]
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_ssm_parameter" {
    defaults = {
      value = "mock-value"
    }
  }

  mock_data "aws_cloudfront_origin_request_policy" {
    defaults = {
      id = "mock-origin-request-policy"
    }
  }
}

# The dev origin remains private and its budget stays a low monthly alert.
run "dev_bucket_and_budget_stay_bounded" {
  command = plan

  variables {
    expected_account_id = "000000000000"
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.dev.block_public_acls,
      aws_s3_bucket_public_access_block.dev.block_public_policy,
      aws_s3_bucket_public_access_block.dev.ignore_public_acls,
      aws_s3_bucket_public_access_block.dev.restrict_public_buckets,
      aws_budgets_budget.dev.limit_amount == "5",
      aws_budgets_budget.dev.limit_unit == "USD",
      aws_budgets_budget.dev.time_unit == "MONTHLY",
    ])
    error_message = "The dev origin must stay private and its budget must remain a five-dollar monthly alert."
  }
}
