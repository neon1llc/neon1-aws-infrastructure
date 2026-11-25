# account/uptime.tf - An outside check of neon1.tech, so an uptime figure rests on data and not on my guess.
# Route 53 asks the home page from several places every 30 seconds, and the alarm emails when it fails
# three checks in a row.


# The home page is served from CloudFront, so a 2xx or 3xx answer means the whole path works
resource "aws_route53_health_check" "site" {
  fqdn              = "neon1.tech"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/"
  request_interval  = 30
  failure_threshold = 3

  tags = {
    Name = "neon1-site"
  }
}


# The alert topic is encrypted with its own key. CloudWatch can't publish through the AWS managed SNS key,
# so the policy lets this account's alarms use this one
resource "aws_kms_key" "uptime" {
  description             = "neon1 uptime alert topic"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministers"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AlarmsPublish"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:SourceAccount" = local.account } }
      },
    ]
  })
}

resource "aws_kms_alias" "uptime" {
  name          = "alias/neon1-uptime"
  target_key_id = aws_kms_key.uptime.key_id
}


# The alarm publishes here, and the function below turns each change into a short email
resource "aws_sns_topic" "uptime" {
  name              = "neon1-uptime"
  kms_master_key_id = aws_kms_key.uptime.arn
}

resource "aws_sns_topic_subscription" "uptime_alert" {
  topic_arn = aws_sns_topic.uptime.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.uptime_alert.arn
}


# --- The plain-language email, sent through neon1-notify ---


data "archive_file" "uptime_alert" {
  type        = "zip"
  source_file = "${path.module}/uptime-alert/index.mjs"
  output_path = "${path.module}/.terraform/uptime-alert.zip"
}

resource "aws_cloudwatch_log_group" "uptime_alert" {
  name              = "/aws/lambda/neon1-uptime-alert"
  retention_in_days = 14
}

resource "aws_iam_role" "uptime_alert" {
  name = "neon1-uptime-alert"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

# Only what it does: write its log, read the alarm's history, and ask neon1-notify to send
resource "aws_iam_role_policy" "uptime_alert" {
  name = "neon1-uptime-alert"
  role = aws_iam_role.uptime_alert.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.uptime_alert.arn}:*" },
      { Effect = "Allow", Action = "cloudwatch:DescribeAlarmHistory", Resource = "arn:aws:cloudwatch:us-east-1:${local.account}:alarm:neon1-site-down" },
      { Effect = "Allow", Action = "lambda:InvokeFunction", Resource = "arn:aws:lambda:us-east-1:${local.account}:function:neon1-notify-prod" },
    ]
  })
}

resource "aws_lambda_function" "uptime_alert" {
  function_name    = "neon1-uptime-alert"
  role             = aws_iam_role.uptime_alert.arn
  runtime          = "nodejs22.x"
  handler          = "index.handler"
  filename         = data.archive_file.uptime_alert.output_path
  source_code_hash = data.archive_file.uptime_alert.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      NOTIFY_FUNCTION = "neon1-notify-prod"
      RECIPIENTS      = join(",", var.alert_emails)
    }
  }

  depends_on = [aws_cloudwatch_log_group.uptime_alert]
}

resource "aws_lambda_permission" "uptime_alert" {
  statement_id  = "AllowUptimeTopic"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.uptime_alert.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.uptime.arn
}


# Route 53 publishes a 1 while the site is healthy and a 0 when it isn't. A missing reading counts as down,
# so a broken check can't read as an outage-free month
resource "aws_cloudwatch_metric_alarm" "site_down" {
  alarm_name          = "neon1-site-down"
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  dimensions          = { HealthCheckId = aws_route53_health_check.site.id }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.uptime.arn]
  ok_actions          = [aws_sns_topic.uptime.arn]
}
