# account/bedrock-guard.tf - Spend guards for Amazon Bedrock, where one unattended evaluation night cost about
# $30 (November 16, 2026). A daily budget emails at the first dollar above its limit; a monthly budget denies
# model calls from the human admin user when it is reached. Production functions are not touched: Neo's own
# monthly caps limit them. To resume after a trip, detach neon1-bedrock-deny from break-glass-admin.

locals {
  bedrock_services = ["Amazon Bedrock", "Claude Sonnet 4.6 (Amazon Bedrock Edition)"]
  admin_user       = "break-glass-admin"
}

resource "aws_budgets_budget" "bedrock_daily" {
  name         = "neon1-bedrock-daily"
  budget_type  = "COST"
  limit_amount = tostring(var.bedrock_daily_usd)
  limit_unit   = "USD"
  time_unit    = "DAILY"

  cost_filter {
    name   = "Service"
    values = local.bedrock_services
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.alert_emails
  }
}

resource "aws_budgets_budget" "bedrock_monthly" {
  name         = "neon1-bedrock-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.bedrock_monthly_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "Service"
    values = local.bedrock_services
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 60
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

data "aws_iam_policy_document" "bedrock_deny" {
  statement {
    sid       = "DenyModelCalls"
    effect    = "Deny"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream", "bedrock:Converse", "bedrock:ConverseStream"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "bedrock_deny" {
  name   = "neon1-bedrock-deny"
  policy = data.aws_iam_policy_document.bedrock_deny.json
}

data "aws_iam_policy_document" "budgets_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "budgets_attach" {
  statement {
    actions   = ["iam:AttachUserPolicy", "iam:DetachUserPolicy"]
    resources = ["arn:aws:iam::${local.account}:user/${local.admin_user}"]
    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values   = [aws_iam_policy.bedrock_deny.arn]
    }
  }
}

resource "aws_iam_role" "budget_action" {
  name               = "neon1-budget-action"
  assume_role_policy = data.aws_iam_policy_document.budgets_assume.json
}

resource "aws_iam_role_policy" "budget_action" {
  role   = aws_iam_role.budget_action.id
  policy = data.aws_iam_policy_document.budgets_attach.json
}

resource "aws_budgets_budget_action" "bedrock_deny" {
  budget_name       = aws_budgets_budget.bedrock_monthly.name
  action_type       = "APPLY_IAM_POLICY"
  approval_model    = "AUTOMATIC"
  notification_type = "ACTUAL"
  action_threshold {
    action_threshold_type  = "PERCENTAGE"
    action_threshold_value = 100
  }
  definition {
    iam_action_definition {
      policy_arn = aws_iam_policy.bedrock_deny.arn
      users      = [local.admin_user]
    }
  }
  execution_role_arn = aws_iam_role.budget_action.arn
  subscriber {
    subscription_type = "EMAIL"
    address           = var.alert_emails[0]
  }
}
