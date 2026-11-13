# site-dev/main.tf - dev.neon1.tech: a private copy of neon1.tech for looking at changes before they
# ship. Its own bucket, distribution, release store, and one function (site/functions/dev-router.js)
# that turns away anyone without the signed cookie sign-in sets (sign-in.tf). Nothing here is shared with
# the live site except the certificate, the hosted zone, and (read-only) the assistant's API.


# The dev host and the AWS managed policies the behaviors use
locals {
  host = "dev.${var.domain}"

  # Same header values as the live site, so dev shows what production would
  hsts_max_age     = 63072000
  permissions_rule = "camera=(), microphone=(), geolocation=(), payment=(), usb=()"

  caching_optimized_policy      = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  caching_disabled_policy       = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  all_viewer_except_host_policy = "b689b0a8-53d0-40ab-baf2-68738e2966ac"

  # The live site's CSP; the portal's adds its documents bucket (the dev one here)
  csp_common = [
    "default-src 'self'",
    "script-src 'self'",
    "style-src 'self'",
    "img-src 'self' data:",
    "font-src 'self'",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
  ]
  csp = {
    site   = join("; ", concat(local.csp_common, ["connect-src 'self'", "upgrade-insecure-requests"]))
    portal = join("; ", concat(local.csp_common, ["connect-src 'self' https://neon1-1neon-docs-dev.s3.us-east-1.amazonaws.com"]))
  }
}


# --- Origin bucket: private, owner-enforced; old versions expire within a week ---


resource "aws_s3_bucket" "dev" {
  bucket        = var.bucket_name
  force_destroy = true # dev content is rebuilt from git at any time
}


# No ACLs and no public access
resource "aws_s3_bucket_ownership_controls" "dev" {
  bucket = aws_s3_bucket.dev.id
  rule { object_ownership = "BucketOwnerEnforced" }
}


resource "aws_s3_bucket_public_access_block" "dev" {
  bucket                  = aws_s3_bucket.dev.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


# Versioned like the live bucket, but dev keeps old copies only a few days
resource "aws_s3_bucket_versioning" "dev" {
  bucket = aws_s3_bucket.dev.id
  versioning_configuration { status = "Enabled" }
}


resource "aws_s3_bucket_lifecycle_configuration" "dev" {
  bucket = aws_s3_bucket.dev.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.dev]
}


# Only the dev distribution may read; listing lets a missing file answer 404 rather than 403
resource "aws_s3_bucket_policy" "dev" {
  bucket = aws_s3_bucket.dev.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowDevCloudFront"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.dev.arn}/*"
        Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.dev.arn } }
      },
      {
        Sid       = "AllowDevCloudFrontMissingAs404"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:ListBucket"
        Resource  = aws_s3_bucket.dev.arn
        Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.dev.arn } }
      },
    ]
  })
}


# --- Things the live site owns, read here ---


# The apex + wildcard certificate (site stack) already covers dev.neon1.tech
data "aws_acm_certificate" "site" {
  domain      = var.domain
  statuses    = ["ISSUED"]
  most_recent = true
}


# The assistant's API and the secret header it requires (neon1-chat's Terraform). Dev uses the live
# assistant: it only answers questions, so nothing dev does can change it
data "aws_ssm_parameter" "chat" {
  for_each = toset(["api_domain", "origin_secret"])
  name     = "/neon1-chat/prod/${each.key}"
}


# The live site's request policy for the assistant: content type and viewer address only
data "aws_cloudfront_origin_request_policy" "chat" {
  name = "neon1-chat-api"
}


# 1NEON's dev backend (neon1-1NEON infra/envs/dev), when portal is on
data "aws_ssm_parameter" "portal" {
  for_each = var.portal ? toset(["app_bucket_domain", "api_domain"]) : toset([])
  name     = "/1neon/dev/${each.key}"
}


# --- Edge: the release store and the gate ---


# The dev release, branch previews ("branch:<name>"), and the cookie key ("session"). The deploy sets
# the releases; the session key is set by hand (neon1-site's make dev-signout) and never passes
# through Terraform state. Terraform owns the store, never its keys
resource "aws_cloudfront_key_value_store" "dev" {
  name    = "neon1-site-dev"
  comment = "dev.neon1.tech release, branch previews, and gate key"
}


# One function for every behavior: the gate, then the live site's or the portal's routing.
# Built from the live routers by site/functions/build-dev.mjs (make dev-router)
resource "aws_cloudfront_function" "dev_router" {
  name    = "neon1-dev-router"
  runtime = "cloudfront-js-2.0"
  comment = "dev.neon1.tech: signed-cookie gate, then the site and portal routers"
  publish = true
  code    = file("${path.module}/../site/functions/dev-router.js")

  key_value_store_associations = [aws_cloudfront_key_value_store.dev.arn]
}


# The live site's and portal's headers, plus noindex on every response
resource "aws_cloudfront_response_headers_policy" "dev" {
  for_each = local.csp

  name    = "neon1-dev-${each.key}-headers"
  comment = "dev.neon1.tech ${each.key} headers (live site's, plus noindex)"

  security_headers_config {
    content_security_policy {
      content_security_policy = each.value
      override                = true
    }
    strict_transport_security {
      access_control_max_age_sec = local.hsts_max_age
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
    content_type_options { override = true }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
  }

  custom_headers_config {
    items {
      header   = "Permissions-Policy"
      value    = local.permissions_rule
      override = true
    }
    items {
      header   = "X-Robots-Tag"
      value    = "noindex, nofollow"
      override = true
    }
  }
}


# CloudFront signs every request to the dev buckets
resource "aws_cloudfront_origin_access_control" "dev" {
  name                              = "neon1-dev-oac"
  description                       = "dev.neon1.tech signs requests to its private S3 origins."
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}


# --- CDN ---


# Shaped like the live distribution; every behavior runs the gate
resource "aws_cloudfront_distribution" "dev" {
  enabled             = true
  comment             = "dev.neon1.tech: private preview of neon1.tech"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  aliases             = [local.host]
  is_ipv6_enabled     = true
  http_version        = "http2"

  # The dev site
  origin {
    origin_id                = "s3-dev"
    domain_name              = aws_s3_bucket.dev.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.dev.id
  }

  default_cache_behavior {
    target_origin_id           = "s3-dev"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = local.caching_optimized_policy
    response_headers_policy_id = aws_cloudfront_response_headers_policy.dev["site"].id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.dev_router.arn
    }
  }

  # Sign-in (sign-in.tf): the edge function answers every request itself, so the origin is never
  # reached and nothing is cached. Listed first so no other pattern can take these paths
  dynamic "ordered_cache_behavior" {
    for_each = toset(["/__signin", "/__auth"])
    content {
      path_pattern               = ordered_cache_behavior.value
      target_origin_id           = "s3-dev"
      viewer_protocol_policy     = "https-only"
      allowed_methods            = ["GET", "HEAD"]
      cached_methods             = ["GET", "HEAD"]
      cache_policy_id            = local.caching_disabled_policy
      response_headers_policy_id = aws_cloudfront_response_headers_policy.dev["site"].id

      lambda_function_association {
        event_type   = "viewer-request"
        lambda_arn   = aws_lambda_function.dev_auth.qualified_arn
        include_body = false
      }
    }
  }

  # The live assistant, behind the same secret header the live site sends
  origin {
    origin_id   = "neon1-chat-api"
    domain_name = data.aws_ssm_parameter.chat["api_domain"].value

    custom_header {
      name  = "x-origin-verify"
      value = data.aws_ssm_parameter.chat["origin_secret"].value
    }

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  ordered_cache_behavior {
    path_pattern               = "/chat/api/*"
    target_origin_id           = "neon1-chat-api"
    viewer_protocol_policy     = "https-only"
    allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = local.caching_disabled_policy
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.chat.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.dev["site"].id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.dev_router.arn
    }
  }

  # --- 1NEON dev backend, when wired in ---

  dynamic "origin" {
    for_each = var.portal ? [1] : []
    content {
      origin_id                = "s3-1neon-app-dev"
      domain_name              = data.aws_ssm_parameter.portal["app_bucket_domain"].value
      origin_access_control_id = aws_cloudfront_origin_access_control.dev.id
    }
  }

  dynamic "origin" {
    for_each = var.portal ? [1] : []
    content {
      origin_id   = "1neon-api-dev"
      domain_name = data.aws_ssm_parameter.portal["api_domain"].value

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  # The portal's API: never cached, cookies and query strings forwarded
  dynamic "ordered_cache_behavior" {
    for_each = var.portal ? [1] : []
    content {
      path_pattern               = "/1NEON/api/*"
      target_origin_id           = "1neon-api-dev"
      viewer_protocol_policy     = "https-only"
      allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods             = ["GET", "HEAD"]
      compress                   = true
      cache_policy_id            = local.caching_disabled_policy
      origin_request_policy_id   = local.all_viewer_except_host_policy
      response_headers_policy_id = aws_cloudfront_response_headers_policy.dev["portal"].id

      function_association {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.dev_router.arn
      }
    }
  }

  # The portal app: static files, app routes rewritten to its shell by the router
  dynamic "ordered_cache_behavior" {
    for_each = var.portal ? [1] : []
    content {
      path_pattern               = "/1NEON*"
      target_origin_id           = "s3-1neon-app-dev"
      viewer_protocol_policy     = "redirect-to-https"
      allowed_methods            = ["GET", "HEAD"]
      cached_methods             = ["GET", "HEAD"]
      compress                   = true
      cache_policy_id            = local.caching_optimized_policy
      response_headers_policy_id = aws_cloudfront_response_headers_policy.dev["portal"].id

      function_association {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.dev_router.arn
      }
    }
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.site.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}


# --- DNS: dev.neon1.tech (A + AAAA) ---


resource "aws_route53_record" "dev" {
  for_each = toset(["A", "AAAA"])

  zone_id = var.zone_id
  name    = local.host
  type    = each.key

  alias {
    name                   = aws_cloudfront_distribution.dev.domain_name
    zone_id                = aws_cloudfront_distribution.dev.hosted_zone_id
    evaluate_target_health = false
  }
}


# --- Values other stacks read (no remote-state coupling) ---


# The github stack scopes the dev deploy role to these; 1NEON's dev stack scopes its app bucket
# to the distribution
resource "aws_ssm_parameter" "dev" {
  for_each = {
    bucket           = aws_s3_bucket.dev.id
    store_arn        = aws_cloudfront_key_value_store.dev.arn
    distribution_id  = aws_cloudfront_distribution.dev.id
    distribution_arn = aws_cloudfront_distribution.dev.arn
  }
  name  = "/neon1-site/dev/${each.key}"
  type  = "String"
  value = each.value
}


# --- Cost: one alert for everything tagged Environment=dev (this stack and 1NEON's dev backend) ---
# Counts only once "Environment" is an active cost allocation tag (Billing > Cost allocation tags)


resource "aws_budgets_budget" "dev" {
  name         = "neon1-dev"
  budget_type  = "COST"
  limit_amount = "5"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:Environment$dev"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}
