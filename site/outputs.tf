# site/outputs.tf - Names other stacks and the site deploy need.


# The origin bucket, the distribution, and the certificate the 1NEON stack reuses
output "bucket" {
  value = aws_s3_bucket.site.id
}


output "distribution_id" {
  value = aws_cloudfront_distribution.site.id
}


output "certificate_arn" {
  value = aws_acm_certificate.site.arn
}
