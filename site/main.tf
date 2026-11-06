# neon1.tech static site: private S3 origin -> CloudFront (OAC) -> Route 53 aliases.
# The hosted zone is owned outside this stack; mail/DKIM records are managed separately.

locals {
  www = "www.${var.domain}"

  # AWS managed policies (stable IDs).
  caching_optimized_policy = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  security_headers_policy  = "67f7725c-6f97-4210-82d7-5512b31e9d03"
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

  origin {
    origin_id                = "s3-website-origin"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id           = "s3-website-origin"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = local.caching_optimized_policy
    response_headers_policy_id = local.security_headers_policy
  }

  # Single-page site: unknown paths render the app instead of an S3 error.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
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
