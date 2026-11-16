# account/outputs.tf - Where the audit trail writes.


output "trail_arn" {
  value = aws_cloudtrail.account.arn
}

output "trail_bucket" {
  value = aws_s3_bucket.trail.bucket
}
