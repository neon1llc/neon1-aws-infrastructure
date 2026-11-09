# github/chat.tf - The role the neon1-chat repository uses to apply its Terraform, which also
# ships the function code.


# Every name the chat stack creates starts with this
locals {
  chat_prefix = "neon1-chat-prod"
}


resource "aws_iam_role" "chat_terraform" {
  name               = "github-neon1-chat-terraform"
  description        = "GitHub Actions Terraform runs for ${local.repos.chat_terraform}"
  assume_role_policy = data.aws_iam_policy_document.trust["chat_terraform"].json
}


# Everything infra/ in neon1-chat creates, each scoped to its names where AWS allows
data "aws_iam_policy_document" "chat_terraform" {
  # Listing the state bucket can't be scoped to a prefix
  statement {
    sid       = "StateList"
    actions   = ["s3:ListBucket"]
    resources = [local.state_arn]
  }

  # State for neon1-chat/* only
  statement {
    sid       = "State"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_arn}/neon1-chat/*"]
  }

  # The counters table, the function, and its log group
  statement {
    sid     = "Resources"
    actions = ["dynamodb:*", "lambda:*", "logs:*"]
    resources = [
      "arn:aws:dynamodb:us-east-1:${local.account}:table/${local.chat_prefix}",
      "arn:aws:lambda:us-east-1:${local.account}:function:${local.chat_prefix}",
      "arn:aws:logs:us-east-1:${local.account}:log-group:/aws/lambda/${local.chat_prefix}*",
    ]
  }

  # Service alarms: their email topic, the alarms themselves, and reading alarm state
  statement {
    sid       = "Alerts"
    actions   = ["sns:*", "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:TagResource", "cloudwatch:UntagResource", "cloudwatch:ListTagsForResource"]
    resources = ["arn:aws:sns:us-east-1:${local.account}:${local.chat_prefix}-*", "arn:aws:cloudwatch:us-east-1:${local.account}:alarm:${local.chat_prefix}-*"]
  }

  # Alarm reads can't be scoped by name
  statement {
    sid       = "AlarmRead"
    actions   = ["cloudwatch:Describe*", "cloudwatch:List*"]
    resources = ["*"]
  }

  # The function's own role; no other IAM. Reading, tagging, trust, removing a policy, and deleting
  # can't widen what a bounded role can do
  statement {
    sid = "FunctionRole"
    actions = [
      "iam:DeleteRole", "iam:GetRole", "iam:TagRole", "iam:UntagRole", "iam:UpdateAssumeRolePolicy",
      "iam:GetRolePolicy", "iam:DeleteRolePolicy", "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole",
    ]
    resources = ["arn:aws:iam::${local.account}:role/${local.chat_prefix}"]
  }

  # Creating the role or writing its policy only with the chat boundary on it (boundaries.tf)
  statement {
    sid       = "BoundedFunctionRole"
    actions   = ["iam:CreateRole", "iam:PutRolePolicy", "iam:PutRolePermissionsBoundary"]
    resources = ["arn:aws:iam::${local.account}:role/${local.chat_prefix}"]
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.boundary_chat.arn]
    }
  }

  # The boundary never comes off, and no managed policy can be attached around it
  statement {
    sid       = "KeepBoundary"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary", "iam:AttachRolePolicy"]
    resources = ["arn:aws:iam::${local.account}:role/${local.chat_prefix}"]
  }

  # That role may only be handed to Lambda
  statement {
    sid       = "PassFunctionRole"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account}:role/${local.chat_prefix}"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }

  # HTTP APIs have generated IDs, so API Gateway can't be scoped by name
  statement {
    sid       = "Api"
    actions   = ["apigateway:*"]
    resources = ["arn:aws:apigateway:us-east-1::/apis", "arn:aws:apigateway:us-east-1::/apis/*", "arn:aws:apigateway:us-east-1::/tags/*"]
  }

  # Its parameters, budget, and the reads Terraform's refresh needs
  statement {
    sid       = "Parameters"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:PutParameter", "ssm:DeleteParameter", "ssm:AddTagsToResource", "ssm:ListTagsForResource"]
    resources = ["arn:aws:ssm:us-east-1:${local.account}:parameter/neon1-chat/*"]
  }

  statement {
    sid       = "Budget"
    actions   = ["budgets:*"]
    resources = ["arn:aws:budgets::${local.account}:budget/${local.chat_prefix}"]
  }

  statement {
    sid       = "Describe"
    actions   = ["logs:DescribeLogGroups", "ssm:DescribeParameters"]
    resources = ["*"]
  }
}


resource "aws_iam_role_policy" "chat_terraform" {
  name   = "terraform"
  role   = aws_iam_role.chat_terraform.id
  policy = data.aws_iam_policy_document.chat_terraform.json
}


# Set as AWS_TERRAFORM_ROLE_ARN in neon1llc/neon1-chat
output "chat_terraform_role_arn" {
  value = aws_iam_role.chat_terraform.arn
}
