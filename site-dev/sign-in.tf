# site-dev/sign-in.tf - Who may sign in to dev.neon1.tech, and the edge function that checks it.
# The secret link (/__signin?k=...) only starts a sign-in at the 1NEON dev pool (auth-dev.neon1.tech);
# a passkey or email code finishes it, and only members of its dev-access group get the cookie.
# Both keys are SSM SecureStrings set by hand (neon1-site make dev-gate / dev-signout), never here.


# --- The 1NEON dev pool (neon1-1NEON infra/envs/dev) and what this stack adds to it ---


data "aws_cognito_user_pools" "dev" {
  name = "1neon-dev"
}


locals {
  pool_id     = one(data.aws_cognito_user_pools.dev.ids)
  auth_domain = "auth-dev.${var.domain}"

  # The two keys: the link starts a sign-in; the session key signs the cookie (also in the store as
  # "session", where dev-gate.js reads it)
  link_param    = "/neon1-site/dev/link_key"
  session_param = "/neon1-site/dev/session_key"
}


# Membership is the whole allow list: add someone here (make dev-allow in neon1-site), and they
# sign in with their own passkey or email code
resource "aws_cognito_user_group" "dev_access" {
  name         = "dev-access"
  user_pool_id = local.pool_id
  description  = "May sign in to dev.neon1.tech"
}


# A public client for the gate alone: code flow with PKCE, back to dev.neon1.tech/__auth
resource "aws_cognito_user_pool_client" "dev_gate" {
  name                                 = "neon1-dev-gate"
  user_pool_id                         = local.pool_id
  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email"]
  callback_urls                        = ["https://${local.host}/__auth"]
  supported_identity_providers         = ["COGNITO"]
  explicit_auth_flows                  = ["ALLOW_USER_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true

  # The cookie carries the session; Cognito's tokens are used once and dropped
  access_token_validity  = 5
  id_token_validity      = 5
  refresh_token_validity = 60
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "minutes"
  }
}


# Managed Login v2 shows a client only once it has a style; Cognito's default for now
resource "aws_cognito_managed_login_branding" "dev_gate" {
  user_pool_id                = local.pool_id
  client_id                   = aws_cognito_user_pool_client.dev_gate.id
  use_cognito_provided_values = true
}


# --- The sign-in function: Lambda@Edge on /__signin and /__auth only ---


# Lambda@Edge has no environment variables, so its settings ride in the zip
data "archive_file" "dev_auth" {
  type        = "zip"
  output_path = "${path.module}/.build/dev-auth.zip"

  source {
    filename = "index.mjs"
    content  = file("${path.module}/../site/functions/dev-auth.mjs")
  }

  source {
    filename = "config.json"
    content = jsonencode({
      authDomain   = local.auth_domain
      clientId     = aws_cognito_user_pool_client.dev_gate.id
      issuer       = "https://cognito-idp.us-east-1.amazonaws.com/${local.pool_id}"
      publicUrl    = "https://${local.host}"
      group        = aws_cognito_user_group.dev_access.name
      linkParam    = local.link_param
      sessionParam = local.session_param
    })
  }
}


# Edge functions run as Lambda and as edgelambda (the copies CloudFront places near viewers)
data "aws_iam_policy_document" "dev_auth_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com", "edgelambda.amazonaws.com"]
    }
  }
}


resource "aws_iam_role" "dev_auth" {
  name               = "neon1-dev-auth"
  description        = "dev.neon1.tech sign-in function: reads its two keys, writes its logs"
  assume_role_policy = data.aws_iam_policy_document.dev_auth_trust.json
}


# Its two keys, and logs in whichever region a copy runs (named us-east-1.neon1-dev-auth there)
data "aws_iam_policy_document" "dev_auth" {
  statement {
    sid       = "Keys"
    actions   = ["ssm:GetParameters"]
    resources = ["arn:aws:ssm:us-east-1:${data.aws_caller_identity.current.account_id}:parameter/neon1-site/dev/*_key"]
  }

  statement {
    sid       = "KeysDecrypt"
    actions   = ["kms:Decrypt"]
    resources = ["arn:aws:kms:us-east-1:${data.aws_caller_identity.current.account_id}:key/*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.us-east-1.amazonaws.com"]
    }
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/us-east-1.neon1-dev-auth*"]
  }
}


resource "aws_iam_role_policy" "dev_auth" {
  name   = "dev-auth"
  role   = aws_iam_role.dev_auth.id
  policy = data.aws_iam_policy_document.dev_auth.json
}


data "aws_caller_identity" "current" {}


# Small and short: viewer-request functions get 128 MB and five seconds. Replicas linger for hours
# after a change, so a destroy here can take a while
resource "aws_lambda_function" "dev_auth" {
  function_name    = "neon1-dev-auth"
  description      = "dev.neon1.tech sign-in: secret link, then a dev-access sign-in"
  role             = aws_iam_role.dev_auth.arn
  runtime          = "nodejs22.x"
  handler          = "index.handler"
  filename         = data.archive_file.dev_auth.output_path
  source_code_hash = data.archive_file.dev_auth.output_base64sha256
  memory_size      = 128
  timeout          = 5
  publish          = true
}
