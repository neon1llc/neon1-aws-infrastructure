# --- 1NEON portal (neon1llc/1NEON): deploy the app, and run its own Terraform ---

locals {
  portal_bucket_arn = "arn:aws:s3:::${var.portal_app_bucket}"
  portal_prefix     = "1neon-prod"
}

# Deploy: sync the SPA, ship the two Lambda bundles, invalidate /1NEON/*.
resource "aws_iam_role" "portal_deploy" {
  name               = "github-1neon-deploy"
  description        = "GitHub Actions deploys for ${local.repos.portal_deploy}"
  assume_role_policy = data.aws_iam_policy_document.trust["portal_deploy"].json
}

data "aws_iam_policy_document" "portal_deploy" {
  statement {
    sid       = "ListApp"
    actions   = ["s3:ListBucket"]
    resources = [local.portal_bucket_arn]
  }

  statement {
    sid       = "WriteApp"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.portal_bucket_arn}/1NEON/*"]
  }

  statement {
    sid       = "ShipFunctions"
    actions   = ["lambda:UpdateFunctionCode", "lambda:GetFunction", "lambda:GetFunctionConfiguration"]
    resources = ["arn:aws:lambda:us-east-1:${local.account}:function:${local.portal_prefix}-*"]
  }

  statement {
    sid       = "Invalidate"
    actions   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
    resources = ["arn:aws:cloudfront::${local.account}:distribution/${var.site_distribution_id}"]
  }
}

resource "aws_iam_role_policy" "portal_deploy" {
  name   = "deploy"
  role   = aws_iam_role.portal_deploy.id
  policy = data.aws_iam_policy_document.portal_deploy.json
}

# Terraform for infra/envs/prod in the 1NEON repo. Every write is scoped to 1NEON's names.
resource "aws_iam_role" "portal_terraform" {
  name               = "github-1neon-terraform"
  description        = "GitHub Actions Terraform runs for ${local.repos.portal_terraform}"
  assume_role_policy = data.aws_iam_policy_document.trust["portal_terraform"].json
}

data "aws_iam_policy_document" "portal_terraform" {
  statement {
    sid       = "StateList"
    actions   = ["s3:ListBucket"]
    resources = [local.state_arn]
  }

  statement {
    sid       = "State"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_arn}/1neon/*"]
  }

  statement {
    sid       = "Buckets"
    actions   = ["s3:*"]
    resources = ["arn:aws:s3:::neon1-1neon-*"]
  }

  statement {
    sid       = "Table"
    actions   = ["dynamodb:*"]
    resources = ["arn:aws:dynamodb:us-east-1:${local.account}:table/${local.portal_prefix}*"]
  }

  statement {
    sid       = "Functions"
    actions   = ["lambda:*"]
    resources = ["arn:aws:lambda:us-east-1:${local.account}:function:${local.portal_prefix}-*"]
  }

  statement {
    sid = "FunctionRoles"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:TagRole", "iam:UntagRole", "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy", "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole",
    ]
    resources = [
      "arn:aws:iam::${local.account}:role/${local.portal_prefix}-*",
      "arn:aws:iam::${local.account}:role/neon1-1neon-*",
    ]
  }

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

  # Cognito, API Gateway, GuardDuty and SES read calls can't be scoped by name.
  statement {
    sid = "Services"
    actions = [
      "cognito-idp:*",
      "apigateway:*",
      "guardduty:*MalwareProtectionPlan*",
      "guardduty:TagResource",
      "guardduty:UntagResource",
      "ses:Get*",
      "ses:List*",
      "logs:DescribeLogGroups",
      "ssm:DescribeParameters",
      "acm:ListCertificates",
      "acm:DescribeCertificate",
      "cloudfront:GetDistribution",
      "cloudwatch:DescribeAlarms",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "Mail"
    actions   = ["ses:*"]
    resources = ["arn:aws:ses:us-east-1:${local.account}:identity/notify.neon1.tech", "arn:aws:ses:us-east-1:${local.account}:configuration-set/${local.portal_prefix}"]
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:*"]
    resources = ["arn:aws:logs:us-east-1:${local.account}:log-group:/aws/lambda/${local.portal_prefix}-*", "arn:aws:logs:us-east-1:${local.account}:log-group:/aws/apigateway/${local.portal_prefix}*"]
  }

  statement {
    sid       = "Alerts"
    actions   = ["sns:*", "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:ListTagsForResource", "cloudwatch:TagResource"]
    resources = ["arn:aws:sns:us-east-1:${local.account}:${local.portal_prefix}-*", "arn:aws:cloudwatch:us-east-1:${local.account}:alarm:${local.portal_prefix}-*"]
  }

  statement {
    sid       = "Budget"
    actions   = ["budgets:*"]
    resources = ["arn:aws:budgets::${local.account}:budget/${local.portal_prefix}"]
  }

  statement {
    sid       = "Parameters"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:PutParameter", "ssm:DeleteParameter", "ssm:AddTagsToResource", "ssm:ListTagsForResource"]
    resources = ["arn:aws:ssm:us-east-1:${local.account}:parameter/1neon/*"]
  }

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

resource "aws_iam_role_policy" "portal_terraform" {
  name   = "terraform"
  role   = aws_iam_role.portal_terraform.id
  policy = data.aws_iam_policy_document.portal_terraform.json
}

# Set as AWS_DEPLOY_ROLE_ARN and AWS_TERRAFORM_ROLE_ARN in neon1llc/1NEON
output "portal_deploy_role_arn" {
  value = aws_iam_role.portal_deploy.arn
}

output "portal_terraform_role_arn" {
  value = aws_iam_role.portal_terraform.arn
}
