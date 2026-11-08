# github/portal.tf - Roles for the 1NEON portal repository: deploying the app and running its
# Terraform.


# --- 1NEON portal (neon1llc/neon1-1NEON): deploy the app, and run its own Terraform ---


# The 1NEON app bucket and the name prefix of its resources
locals {
  portal_bucket_arn = "arn:aws:s3:::${var.portal_app_bucket}"
  portal_prefix     = "1neon-prod"
  # The function and scanner roles 1NEON's Terraform manages
  portal_role_arns = [
    "arn:aws:iam::${local.account}:role/${local.portal_prefix}-*",
    "arn:aws:iam::${local.account}:role/neon1-1neon-*",
  ]
}


# Deploy: sync the SPA, ship the two Lambda bundles, invalidate /1NEON/*.
resource "aws_iam_role" "portal_deploy" {
  name               = "github-1neon-deploy"
  description        = "GitHub Actions deploys for ${local.repos.portal_deploy}"
  assume_role_policy = data.aws_iam_policy_document.trust["portal_deploy"].json
}


# Write the app's files, update function code, and invalidate the CDN
data "aws_iam_policy_document" "portal_deploy" {
  # Sync needs to list the bucket to find deleted files
  statement {
    sid       = "ListApp"
    actions   = ["s3:ListBucket"]
    resources = [local.portal_bucket_arn]
  }

  # The app's files live under 1NEON/ in its bucket; nothing else is writable
  statement {
    sid       = "WriteApp"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.portal_bucket_arn}/1NEON/*"]
  }

  # Upload new code to the two existing functions; their settings stay with Terraform
  statement {
    sid       = "ShipFunctions"
    actions   = ["lambda:UpdateFunctionCode", "lambda:GetFunction", "lambda:GetFunctionConfiguration"]
    resources = ["arn:aws:lambda:us-east-1:${local.account}:function:${local.portal_prefix}-*"]
  }

  # Clear /1NEON/* from the CDN after a deploy
  statement {
    sid       = "Invalidate"
    actions   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
    resources = ["arn:aws:cloudfront::${local.account}:distribution/${var.site_distribution_id}"]
  }
}


# Attach the deploy policy to the portal deploy role
resource "aws_iam_role_policy" "portal_deploy" {
  name   = "deploy"
  role   = aws_iam_role.portal_deploy.id
  policy = data.aws_iam_policy_document.portal_deploy.json
}


# Terraform for infra/envs/prod in the 1NEON repo. Every write is scoped to 1NEON's names
resource "aws_iam_role" "portal_terraform" {
  name               = "github-1neon-terraform"
  description        = "GitHub Actions Terraform runs for ${local.repos.portal_terraform}"
  assume_role_policy = data.aws_iam_policy_document.trust["portal_terraform"].json
}


# Everything infra/envs/prod creates, each scoped to 1NEON's names where AWS allows
data "aws_iam_policy_document" "portal_terraform" {
  statement {
    # Listing the state bucket can't be scoped to a prefix
    sid       = "StateList"
    actions   = ["s3:ListBucket"]
    resources = [local.state_arn]
  }

  # State for 1neon/* only; other stacks' state stays out of reach
  statement {
    sid       = "State"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_arn}/1neon/*"]
  }

  # The app and documents buckets (neon1-1neon-*)
  statement {
    sid       = "Buckets"
    actions   = ["s3:CreateBucket", "s3:Get*", "s3:List*", "s3:Put*", "s3:Delete*"]
    resources = ["arn:aws:s3:::neon1-1neon-*"]
  }

  # The single table
  statement {
    sid       = "Table"
    actions   = ["dynamodb:*"]
    resources = ["arn:aws:dynamodb:us-east-1:${local.account}:table/${local.portal_prefix}*"]
  }

  # The API and trigger functions
  statement {
    sid       = "Functions"
    actions   = ["lambda:*"]
    resources = ["arn:aws:lambda:us-east-1:${local.account}:function:${local.portal_prefix}-*"]
  }

  # Roles for 1NEON's own functions and the malware scanner; no other IAM. Reading, tagging, trust,
  # removing a policy, and deleting can't widen what a bounded role can do
  statement {
    sid = "FunctionRoles"
    actions = [
      "iam:DeleteRole", "iam:GetRole", "iam:TagRole", "iam:UntagRole", "iam:UpdateAssumeRolePolicy",
      "iam:GetRolePolicy", "iam:DeleteRolePolicy", "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole",
    ]
    resources = local.portal_role_arns
  }

  # Creating a role or writing its policy only with the 1NEON boundary on it (boundaries.tf)
  statement {
    sid       = "BoundedFunctionRoles"
    actions   = ["iam:CreateRole", "iam:PutRolePolicy", "iam:PutRolePermissionsBoundary"]
    resources = local.portal_role_arns
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.boundary_portal.arn]
    }
  }

  # The boundary never comes off, and no managed policy can be attached around it
  statement {
    sid       = "KeepBoundary"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary", "iam:AttachRolePolicy"]
    resources = local.portal_role_arns
  }

  # Those roles may only be handed to Lambda or GuardDuty
  statement {
    sid       = "PassFunctionRoles"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account}:role/${local.portal_prefix}-*", "arn:aws:iam::${local.account}:role/neon1-1neon-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com", "malware-protection-plan.guardduty.amazonaws.com"]
    }
  }

  # Cognito, API Gateway, GuardDuty and SES read calls can't be scoped by name
  statement {
    sid = "Services"
    actions = [
      "cognito-idp:*",
      "apigateway:*",
      "guardduty:*MalwareProtectionPlan*",
      "guardduty:TagResource",
      "guardduty:UntagResource",
      "guardduty:ListTagsForResource",
      "ses:Get*",
      "ses:List*",
      "logs:DescribeLogGroups",
      "ssm:DescribeParameters",
      "acm:Describe*",
      "acm:Get*",
      "acm:List*",
      "cloudfront:Get*",
      "cloudfront:List*",
      "cloudwatch:Describe*",
      "cloudwatch:List*",
    ]
    resources = ["*"]
  }

  # Text messages: 1NEON's toll-free number and its opt-out list (the only texting in this account)
  statement {
    sid = "Texts"
    actions = [
      "sms-voice:RequestPhoneNumber", "sms-voice:ReleasePhoneNumber", "sms-voice:UpdatePhoneNumber", "sms-voice:DescribePhoneNumbers",
      "sms-voice:CreateOptOutList", "sms-voice:DeleteOptOutList", "sms-voice:DescribeOptOutLists", "sms-voice:DescribeOptedOutNumbers",
      "sms-voice:TagResource", "sms-voice:UntagResource", "sms-voice:ListTagsForResource",
    ]
    resources = ["arn:aws:sms-voice:us-east-1:${local.account}:*"]
  }

  # The notify.neon1.tech identity and its configuration set
  statement {
    sid       = "Mail"
    actions   = ["ses:*"]
    resources = ["arn:aws:ses:us-east-1:${local.account}:identity/notify.neon1.tech", "arn:aws:ses:us-east-1:${local.account}:configuration-set/${local.portal_prefix}"]
  }

  # 1NEON log groups only
  statement {
    sid       = "Logs"
    actions   = ["logs:*"]
    resources = ["arn:aws:logs:us-east-1:${local.account}:log-group:/aws/lambda/${local.portal_prefix}-*", "arn:aws:logs:us-east-1:${local.account}:log-group:/aws/apigateway/${local.portal_prefix}*"]
  }

  # Alarm topic and alarms
  statement {
    sid       = "Alerts"
    actions   = ["sns:*", "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:ListTagsForResource", "cloudwatch:TagResource"]
    resources = ["arn:aws:sns:us-east-1:${local.account}:${local.portal_prefix}-*", "arn:aws:cloudwatch:us-east-1:${local.account}:alarm:${local.portal_prefix}-*"]
  }

  # The portal's own budget
  statement {
    sid       = "Budget"
    actions   = ["budgets:*"]
    resources = ["arn:aws:budgets::${local.account}:budget/${local.portal_prefix}"]
  }

  # Parameters under /1neon/, including the ones the edge reads
  statement {
    sid       = "Parameters"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:PutParameter", "ssm:DeleteParameter", "ssm:AddTagsToResource", "ssm:ListTagsForResource"]
    resources = ["arn:aws:ssm:us-east-1:${local.account}:parameter/1neon/*"]
  }

  # Read the zone and wait for record changes
  statement {
    sid       = "ZoneRead"
    actions   = ["route53:GetHostedZone", "route53:ListResourceRecordSets", "route53:ListTagsForResource", "route53:GetChange"]
    resources = ["arn:aws:route53:::hostedzone/${var.zone_id}", "arn:aws:route53:::change/*"]
  }

  # auth.neon1.tech alias, and the notify.neon1.tech mail records (DKIM, MAIL FROM, DMARC)
  statement {
    sid       = "ZoneRecords"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${var.zone_id}"]
    condition {
      test     = "ForAllValues:StringLike"
      variable = "route53:ChangeResourceRecordSetsNormalizedRecordNames"
      values   = ["auth.neon1.tech", "*.notify.neon1.tech", "notify.neon1.tech"]
    }
  }
}


# Attach the Terraform policy to the portal Terraform role
resource "aws_iam_role_policy" "portal_terraform" {
  name   = "terraform"
  role   = aws_iam_role.portal_terraform.id
  policy = data.aws_iam_policy_document.portal_terraform.json
}


# Set as AWS_DEPLOY_ROLE_ARN and AWS_TERRAFORM_ROLE_ARN in neon1llc/neon1-1NEON
output "portal_deploy_role_arn" {
  value = aws_iam_role.portal_deploy.arn
}


output "portal_terraform_role_arn" {
  value = aws_iam_role.portal_terraform.arn
}
