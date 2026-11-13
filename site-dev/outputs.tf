# site-dev/outputs.tf - Names the dev deploy, the github stack, and 1NEON's dev stack need.


# The dev bucket and distribution
output "bucket" {
  value = aws_s3_bucket.dev.id
}


output "distribution_id" {
  value = aws_cloudfront_distribution.dev.id
}


# The store holding the gate key, the dev release, and branch previews
output "store_arn" {
  value = aws_cloudfront_key_value_store.dev.arn
}


output "url" {
  value = "https://${local.host}/"
}
