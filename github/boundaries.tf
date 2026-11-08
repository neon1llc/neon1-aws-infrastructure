# github/boundaries.tf - Permission ceilings for the roles that the 1NEON and neon1-chat Terraform
# roles create for their own functions. Those Terraform roles may create or change a function role
# only with its boundary attached, and may never remove it, so a compromised workflow can't write
# itself a role that reaches past its own app. The boundaries live here, where only a person applies.


# --- 1NEON: the API, the sign-up trigger, and the GuardDuty malware scanner ---

data "aws_iam_policy_document" "boundary_portal" {
  # Its own log groups
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:us-east-1:${local.account}:log-group:/aws/lambda/${local.portal_prefix}-*"]
  }

  # Item reads and writes on its table; no table management
  statement {
    sid       = "Table"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:BatchGetItem", "dynamodb:ConditionCheckItem"]
    resources = ["arn:aws:dynamodb:us-east-1:${local.account}:table/${local.portal_prefix}*"]
  }

  # Objects in its own buckets, including the scanner's tags and versions
  statement {
    sid = "Objects"
    actions = [
      "s3:GetObject", "s3:GetObjectVersion", "s3:GetObjectAttributes", "s3:PutObject", "s3:DeleteObject",
      "s3:GetObjectTagging", "s3:GetObjectVersionTagging", "s3:PutObjectTagging", "s3:PutObjectVersionTagging",
    ]
    resources = ["arn:aws:s3:::neon1-1neon-*/*"]
  }

  # The scanner watches its bucket through notifications
  statement {
    sid       = "Buckets"
    actions   = ["s3:ListBucket", "s3:GetBucketNotification", "s3:PutBucketNotification"]
    resources = ["arn:aws:s3:::neon1-1neon-*"]
  }

  # Invites and account switches in the user pool
  statement {
    sid       = "Directory"
    actions   = ["cognito-idp:AdminGetUser", "cognito-idp:AdminCreateUser", "cognito-idp:AdminDisableUser", "cognito-idp:AdminEnableUser", "cognito-idp:AdminUserGlobalSignOut"]
    resources = ["arn:aws:cognito-idp:us-east-1:${local.account}:userpool/*"]
  }

  # Mail from notify.neon1.tech only
  statement {
    sid       = "Mail"
    actions   = ["ses:SendEmail", "ses:SendRawEmail"]
    resources = ["arn:aws:ses:us-east-1:${local.account}:identity/notify.neon1.tech", "arn:aws:ses:us-east-1:${local.account}:configuration-set/${local.portal_prefix}"]
  }

  # The EventBridge rules GuardDuty manages for the scan
  statement {
    sid       = "ScanRules"
    actions   = ["events:PutRule", "events:DeleteRule", "events:PutTargets", "events:RemoveTargets", "events:DescribeRule"]
    resources = ["arn:aws:events:us-east-1:${local.account}:rule/DO-NOT-DELETE-AmazonGuardDutyMalwareProtectionS3*"]
  }
}

resource "aws_iam_policy" "boundary_portal" {
  name        = "neon1-boundary-1neon"
  description = "Ceiling for 1NEON function and scanner roles"
  policy      = data.aws_iam_policy_document.boundary_portal.json
}


# --- neon1-chat: one function that calls one model family and counts in one table ---

data "aws_iam_policy_document" "boundary_chat" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:us-east-1:${local.account}:log-group:/aws/lambda/${local.chat_prefix}*"]
  }

  # Model calls only; any inference profile in the account and the US foundation models it routes to
  statement {
    sid       = "Model"
    actions   = ["bedrock:InvokeModel"]
    resources = ["arn:aws:bedrock:us-east-1:${local.account}:inference-profile/*", "arn:aws:bedrock:us-*::foundation-model/*"]
  }

  statement {
    sid       = "Counters"
    actions   = ["dynamodb:UpdateItem"]
    resources = ["arn:aws:dynamodb:us-east-1:${local.account}:table/${local.chat_prefix}"]
  }
}

resource "aws_iam_policy" "boundary_chat" {
  name        = "neon1-boundary-chat"
  description = "Ceiling for the neon1-chat function role"
  policy      = data.aws_iam_policy_document.boundary_chat.json
}


# Set as the permissions_boundary on those roles in each repository
output "portal_boundary_arn" {
  value = aws_iam_policy.boundary_portal.arn
}

output "chat_boundary_arn" {
  value = aws_iam_policy.boundary_chat.arn
}
