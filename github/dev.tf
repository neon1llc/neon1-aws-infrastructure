# github/dev.tf - dev.neon1.tech: deploy roles for the site and 1NEON previews, and the permission
# ceiling for 1NEON's dev functions. Dev roles trust every branch of their repository (any branch can
# be previewed), so each one reaches only dev resources: the dev bucket, the dev store, and names
# under 1neon-dev. Nothing here can touch neon1.tech or 1NEON production.


# What site-dev publishes about itself; apply site-dev before this stack
data "aws_ssm_parameter" "site_dev" {
  for_each = toset(["bucket", "store_arn", "distribution_id"])
  name     = "/neon1-site/dev/${each.key}"
}


locals {
  dev_bucket_arn = "arn:aws:s3:::${data.aws_ssm_parameter.site_dev["bucket"].value}"
  dev_dist_arn   = "arn:aws:cloudfront::${local.account}:distribution/${data.aws_ssm_parameter.site_dev["distribution_id"].value}"
  portal_dev     = "1neon-dev"

  dev_subjects = {
    site   = "repo:${var.github_org}/${var.site_repo}:ref:refs/heads/*"
    portal = "repo:${var.portal_subject}:ref:refs/heads/*"
  }
}


# Any branch of the one repository; pull requests from forks get a different subject and can't
data "aws_iam_policy_document" "dev_trust" {
  for_each = local.dev_subjects

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${local.oidc_host}:sub"
      values   = [each.value]
    }
  }
}


# --- Site: upload a dev release or a branch preview and switch to it ---


resource "aws_iam_role" "site_dev_deploy" {
  name               = "github-neon1-site-dev-deploy"
  description        = "GitHub Actions dev.neon1.tech deploys for any branch of ${local.repos.site_deploy}"
  assume_role_policy = data.aws_iam_policy_document.dev_trust["site"].json
}


# The dev bucket and the dev store only
data "aws_iam_policy_document" "site_dev_deploy" {
  statement {
    sid       = "ListDev"
    actions   = ["s3:ListBucket"]
    resources = [local.dev_bucket_arn]
  }

  statement {
    sid       = "WriteDev"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.dev_bucket_arn}/*"]
  }

  # The release keys; the deploy also reads "gate" only to know it exists, never to print it
  statement {
    sid = "SwitchDevRelease"
    actions = [
      "cloudfront:DescribeKeyValueStore",
      "cloudfront-keyvaluestore:DescribeKeyValueStore",
      "cloudfront-keyvaluestore:GetKey",
      "cloudfront-keyvaluestore:ListKeys",
      "cloudfront-keyvaluestore:PutKey",
      "cloudfront-keyvaluestore:DeleteKey",
      "cloudfront-keyvaluestore:UpdateKeys",
    ]
    resources = [data.aws_ssm_parameter.site_dev["store_arn"].value]
  }
}


resource "aws_iam_role_policy" "site_dev_deploy" {
  name   = "deploy"
  role   = aws_iam_role.site_dev_deploy.id
  policy = data.aws_iam_policy_document.site_dev_deploy.json
}


# --- 1NEON: ship the app and functions to the dev backend ---


resource "aws_iam_role" "portal_dev_deploy" {
  name               = "github-1neon-dev-deploy"
  description        = "GitHub Actions 1NEON dev deploys for any branch of ${local.repos.portal_deploy}"
  assume_role_policy = data.aws_iam_policy_document.dev_trust["portal"].json
}


# The dev app bucket, the dev functions, and the dev distribution's cache
data "aws_iam_policy_document" "portal_dev_deploy" {
  statement {
    sid       = "ListApp"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::neon1-1neon-app-dev"]
  }

  statement {
    sid       = "WriteApp"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::neon1-1neon-app-dev/1NEON/*"]
  }

  statement {
    sid       = "ShipFunctions"
    actions   = ["lambda:UpdateFunctionCode", "lambda:GetFunction", "lambda:GetFunctionConfiguration"]
    resources = ["arn:aws:lambda:us-east-1:${local.account}:function:${local.portal_dev}-*"]
  }

  statement {
    sid       = "Invalidate"
    actions   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
    resources = [local.dev_dist_arn]
  }

  # The workflow finds the dev distribution by what site-dev publishes
  statement {
    sid       = "FindDev"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:us-east-1:${local.account}:parameter/neon1-site/dev/*"]
  }
}


resource "aws_iam_role_policy" "portal_dev_deploy" {
  name   = "deploy"
  role   = aws_iam_role.portal_dev_deploy.id
  policy = data.aws_iam_policy_document.portal_dev_deploy.json
}


# --- Ceiling for 1NEON's dev function roles (neon1-1NEON infra/envs/dev attaches it) ---
# Like production's, but scoped to 1neon-dev names, its own parameters, and a user pool tagged
# Environment=dev. No texts, and mail only through the dev configuration set


data "aws_iam_policy_document" "boundary_portal_dev" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:us-east-1:${local.account}:log-group:/aws/lambda/${local.portal_dev}-*"]
  }

  statement {
    sid       = "Table"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:BatchGetItem", "dynamodb:ConditionCheckItem"]
    resources = ["arn:aws:dynamodb:us-east-1:${local.account}:table/${local.portal_dev}*"]
  }

  statement {
    sid = "Objects"
    actions = [
      "s3:GetObject", "s3:GetObjectVersion", "s3:GetObjectAttributes", "s3:PutObject", "s3:DeleteObject",
      "s3:GetObjectTagging", "s3:GetObjectVersionTagging", "s3:PutObjectTagging", "s3:PutObjectVersionTagging",
      "s3:PutObjectRetention",
    ]
    resources = ["arn:aws:s3:::neon1-1neon-*-dev/*"]
  }

  statement {
    sid       = "Buckets"
    actions   = ["s3:ListBucket", "s3:GetBucketNotification", "s3:PutBucketNotification"]
    resources = ["arn:aws:s3:::neon1-1neon-*-dev"]
  }

  statement {
    sid       = "Secrets"
    actions   = ["ssm:GetParameters"]
    resources = ["arn:aws:ssm:us-east-1:${local.account}:parameter/1neon/dev/*"]
  }

  statement {
    sid       = "SecretsKey"
    actions   = ["kms:Decrypt"]
    resources = ["arn:aws:kms:us-east-1:${local.account}:key/*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.us-east-1.amazonaws.com"]
    }
  }

  # Only a pool tagged Environment=dev; production's carries Environment=prod
  statement {
    sid       = "Directory"
    actions   = ["cognito-idp:AdminGetUser", "cognito-idp:AdminCreateUser", "cognito-idp:AdminDisableUser", "cognito-idp:AdminEnableUser", "cognito-idp:AdminUserGlobalSignOut"]
    resources = ["arn:aws:cognito-idp:us-east-1:${local.account}:userpool/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = ["dev"]
    }
  }

  statement {
    sid       = "Mail"
    actions   = ["ses:SendEmail", "ses:SendRawEmail"]
    resources = ["arn:aws:ses:us-east-1:${local.account}:identity/notify.neon1.tech", "arn:aws:ses:us-east-1:${local.account}:configuration-set/${local.portal_dev}"]
  }

  statement {
    sid       = "Model"
    actions   = ["bedrock:InvokeModel"]
    resources = ["arn:aws:bedrock:us-east-1:${local.account}:inference-profile/us.${var.portal_neo_model_id}", "arn:aws:bedrock:us-*::foundation-model/${var.portal_neo_model_id}"]
  }
}

resource "aws_iam_policy" "boundary_portal_dev" {
  name        = "neon1-boundary-1neon-dev"
  description = "Ceiling for 1NEON dev function roles"
  policy      = data.aws_iam_policy_document.boundary_portal_dev.json
}


# Set as AWS_DEV_DEPLOY_ROLE_ARN in neon1-site and neon1-1NEON
output "site_dev_deploy_role_arn" {
  value = aws_iam_role.site_dev_deploy.arn
}

output "portal_dev_deploy_role_arn" {
  value = aws_iam_role.portal_dev_deploy.arn
}
