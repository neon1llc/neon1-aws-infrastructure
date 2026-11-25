# site/not-found.tf - The edge function that turns S3's errors into the not-found page on neon1.tech.
# CloudFront Functions don't run on origin errors, and a distribution-wide error page would replace
# the APIs' own errors, so an origin-response Lambda@Edge sits on the two S3 behaviors only.


# Lambda@Edge has no environment variables and needs no config; the zip is just the function
data "archive_file" "not_found" {
  type        = "zip"
  output_path = "${path.module}/.build/not-found.zip"

  source {
    filename = "index.mjs"
    content  = file("${path.module}/functions/not-found-edge.mjs")
  }
}


# Edge functions run as Lambda and as edgelambda (the copies CloudFront places near viewers)
data "aws_iam_policy_document" "not_found_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com", "edgelambda.amazonaws.com"]
    }
  }
}


resource "aws_iam_role" "not_found" {
  name               = "neon1-site-not-found"
  description        = "neon1.tech not-found function: writes its logs, reads nothing"
  assume_role_policy = data.aws_iam_policy_document.not_found_trust.json
}


data "aws_caller_identity" "current" {}


# Logs in whichever region a copy runs (named us-east-1.neon1-site-not-found there)
data "aws_iam_policy_document" "not_found" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/us-east-1.neon1-site-not-found*"]
  }
}


resource "aws_iam_role_policy" "not_found" {
  name   = "not-found"
  role   = aws_iam_role.not_found.id
  policy = data.aws_iam_policy_document.not_found.json
}


# Small and short: it only swaps a body
resource "aws_lambda_function" "not_found" {
  function_name    = "neon1-site-not-found"
  description      = "neon1.tech: S3 errors become the not-found page with a 404"
  role             = aws_iam_role.not_found.arn
  runtime          = "nodejs22.x"
  handler          = "index.handler"
  filename         = data.archive_file.not_found.output_path
  source_code_hash = data.archive_file.not_found.output_base64sha256
  memory_size      = 128
  timeout          = 5
  publish          = true
}
