# catchall/main.tf - Every neon1.tech name nothing else claims (test.neon1.tech and the like) shows
# neon1's not-found page with a 404 instead of the browser's own error. A wildcard record and its own
# small distribution: exact names (the site, dev, auth, admin-dev) always win over the wildcard, in DNS
# and in CloudFront, so this stack changes none of them. Its only origin is neon1.tech's public files.


locals {
  wildcard = "*.${var.domain}"
  # AWS managed cache policy: caching optimized
  caching_optimized_policy = "658327ea-f89d-4fab-a63d-7e88639e58f6"
}


# The apex + wildcard certificate (site stack)
data "aws_acm_certificate" "site" {
  domain      = var.domain
  statuses    = ["ISSUED"]
  most_recent = true
}


resource "aws_cloudfront_function" "catchall" {
  name    = "neon1-catchall"
  runtime = "cloudfront-js-2.0"
  comment = "Unclaimed neon1.tech names: the not-found page"
  publish = true
  code    = file("${path.module}/../site/functions/catchall.js")
}


# The live site's headers, plus noindex
resource "aws_cloudfront_response_headers_policy" "catchall" {
  name    = "neon1-catchall-headers"
  comment = "Unclaimed neon1.tech names: security headers and noindex"

  security_headers_config {
    content_security_policy {
      content_security_policy = "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
      override                = true
    }
    strict_transport_security {
      access_control_max_age_sec = 63072000
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
    # The same Permissions-Policy the site sends, so every neon1.tech name answers alike
    items {
      header   = "Permissions-Policy"
      value    = "camera=(), microphone=(), geolocation=(), payment=(), usb=()"
      override = true
    }
    items {
      header   = "X-Robots-Tag"
      value    = "noindex, nofollow"
      override = true
    }
  }

  remove_headers_config {
    items {
      header = "Server"
    }
  }
}


resource "aws_cloudfront_distribution" "catchall" {
  enabled         = true
  comment         = "Unclaimed neon1.tech names: the not-found page"
  price_class     = "PriceClass_100"
  aliases         = [local.wildcard]
  is_ipv6_enabled = true
  http_version    = "http2"

  origin {
    origin_id   = "neon1-site"
    domain_name = var.domain

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id           = "neon1-site"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = local.caching_optimized_policy
    response_headers_policy_id = aws_cloudfront_response_headers_policy.catchall.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.catchall.arn
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


resource "aws_route53_record" "wildcard" {
  for_each = toset(["A", "AAAA"])

  zone_id = var.zone_id
  name    = local.wildcard
  type    = each.key

  alias {
    name                   = aws_cloudfront_distribution.catchall.domain_name
    zone_id                = aws_cloudfront_distribution.catchall.hosted_zone_id
    evaluate_target_health = false
  }
}
