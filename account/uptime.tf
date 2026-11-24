# account/uptime.tf - An outside check of neon1.tech, so an uptime figure rests on data and not on my guess.
# Route 53 asks the home page from several places every 30 seconds, and the alarm emails when it fails
# three checks in a row. Confirm the email subscriptions once from the inbox.


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


# Where the alarm sends its email
resource "aws_sns_topic" "uptime" {
  name              = "neon1-uptime"
  kms_master_key_id = aws_kms_key.uptime.arn
}

resource "aws_sns_topic_subscription" "uptime" {
  for_each  = toset(var.alert_emails)
  topic_arn = aws_sns_topic.uptime.arn
  protocol  = "email"
  endpoint  = each.value
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
