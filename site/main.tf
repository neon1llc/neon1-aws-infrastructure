# neon1.tech static site: private S3 origin -> CloudFront (OAC) -> Route 53 aliases.
# The hosted zone is owned outside this stack; mail/DKIM records are managed separately.

locals {
  www = "www.${var.domain}"

  # AWS managed policies (stable IDs).
  caching_optimized_policy = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  security_headers_policy  = "67f7725c-6f97-4210-82d7-5512b31e9d03"
  caching_disabled_policy  = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

  all_viewer_except_host_policy = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
}

# --- Origin bucket: private, owner-enforced, versioned so a bad deploy can roll back ---

resource "aws_s3_bucket" "site" {
  bucket = var.bucket_name

  # Content outlives infrastructure changes; never delete objects implicitly.
  force_destroy = false
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id
  versioning_configuration { status = "Enabled" }
}

# Keep rollback history bounded so old versions don't accrue cost.
resource "aws_s3_bucket_lifecycle_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days           = 30
      newer_noncurrent_versions = 5
    }
  }

  depends_on = [aws_s3_bucket_versioning.site]
}

# Only this distribution may read objects.
resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontOAC"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.site.arn}/*"
      Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.site.arn } }
    }]
  })
}

# --- TLS: apex + wildcard so any future subdomain (www, portal, dev...) is covered ---

resource "aws_acm_certificate" "site" {
  domain_name               = var.domain
  subject_alternative_names = ["*.${var.domain}"]
  validation_method         = "DNS"

  lifecycle { create_before_destroy = true }
}

# Apex and wildcard share one validation record; dedupe by name.
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for o in aws_acm_certificate.site.domain_validation_options : o.resource_record_name => o...
  }

  zone_id         = var.zone_id
  name            = each.key
  type            = each.value[0].resource_record_type
  records         = [each.value[0].resource_record_value]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "site" {
  certificate_arn         = aws_acm_certificate.site.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# --- CDN ---

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "neon1-website-oac"
  description                       = "Allows CloudFront to sign requests to the private S3 origin using SigV4."
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  comment             = "neon1 website distribution — S3 private origin behind CloudFront"
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # US/EU edges: cheapest tier that fits the audience
  aliases             = [var.domain, local.www]
  is_ipv6_enabled     = true
  http_version        = "http2and3"

  # Marketing site: the private website bucket.
  origin {
    origin_id                = "s3-website-origin"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  # Everything not matched below is the marketing site.
  default_cache_behavior {
    target_origin_id           = "s3-website-origin"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = local.caching_optimized_policy
    response_headers_policy_id = local.security_headers_policy

    # Unknown page paths render the site; missing files stay real errors.
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.site_router.arn
    }
  }

  # --- 1NEON portal at /1NEON (resources owned by the neon1llc/1NEON repo) ---

  origin {
    origin_id                = "s3-1neon-app"
    domain_name              = data.aws_ssm_parameter.portal["app_bucket_domain"].value
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  origin {
    origin_id   = "1neon-api"
    domain_name = data.aws_ssm_parameter.portal["api_domain"].value

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # API first: never cached, every method, cookies and query strings forwarded.
  ordered_cache_behavior {
    path_pattern               = "/1NEON/api/*"
    target_origin_id           = "1neon-api"
    viewer_protocol_policy     = "https-only"
    allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = local.caching_disabled_policy
    origin_request_policy_id   = local.all_viewer_except_host_policy
    response_headers_policy_id = aws_cloudfront_response_headers_policy.portal.id
  }

  # The portal app: cached static files, app routes rewritten to its shell.
  ordered_cache_behavior {
    path_pattern               = "/1NEON*"
    target_origin_id           = "s3-1neon-app"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = local.caching_optimized_policy
    response_headers_policy_id = aws_cloudfront_response_headers_policy.portal.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.portal_router.arn
    }
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.site.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# --- DNS: apex and www alias straight to the CDN (A + AAAA) ---

resource "aws_route53_record" "alias" {
  for_each = {
    for pair in setproduct([var.domain, local.www], ["A", "AAAA"]) : "${pair[0]}-${pair[1]}" => pair
  }

  zone_id = var.zone_id
  name    = each.value[0]
  type    = each.value[1]

  # Take over the hand-made records in place (UPSERT) rather than failing on conflict.
  allow_overwrite = true

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

# --- Edge functions: page routing without distribution-wide error pages ---
# The old 403/404 -> /index.html rule applied to every path, which would have turned
# portal API errors into the marketing page. Routing now happens per behavior.

resource "aws_cloudfront_function" "site_router" {
  name    = "neon1-site-router"
  runtime = "cloudfront-js-2.0"
  comment = "neon1.tech: paths without a file extension render index.html"
  publish = true
  code    = file("${path.module}/functions/site-router.js")
}

resource "aws_cloudfront_function" "portal_router" {
  name    = "neon1-1neon-router"
  runtime = "cloudfront-js-2.0"
  comment = "1NEON: /1NEON -> /1NEON/, app routes render /1NEON/index.html"
  publish = true
  code    = file("${path.module}/functions/portal-router.js")
}

# Strict headers for the portal: same-origin scripts and connections only.
resource "aws_cloudfront_response_headers_policy" "portal" {
  name    = "neon1-1neon-headers"
  comment = "1NEON portal security headers"

  security_headers_config {
    content_security_policy {
      content_security_policy = join("; ", [
        "default-src 'self'",
        "script-src 'self'",
        "style-src 'self'",
        "img-src 'self' data:",
        "font-src 'self'",
        "connect-src 'self'",
        "object-src 'none'",
        "base-uri 'self'",
        "form-action 'self'",
        "frame-ancestors 'none'",
      ])
      override = true
    }
    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = true
      preload                    = false
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
      value    = "camera=(), microphone=(), geolocation=(), payment=()"
      override = true
    }
  }
}

# Published by the 1NEON repo's Terraform (infra/envs/prod). Apply that stack first.
data "aws_ssm_parameter" "portal" {
  for_each = toset(["app_bucket_domain", "api_domain"])
  name     = "/1neon/prod/${each.key}"
}
