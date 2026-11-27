mock_provider "aws" {}

run "rejects_non_account_id" {
  command = plan

  variables {
    expected_account_id = "not-an-account-id"
  }

  expect_failures = [var.expected_account_id]
}
