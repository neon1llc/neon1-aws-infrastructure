# site

Static hosting for **neon1.tech**: private S3 origin, CloudFront with Origin Access Control, an ACM certificate for `neon1.tech` + `*.neon1.tech`, and Route 53 A/AAAA aliases for the apex and `www`.

The hosted zone itself and mail records are outside this stack.

```bash
export AWS_PROFILE=neon1
terraform init
terraform plan
terraform apply
```

State is stored in `s3://neon1-tfstate/site/terraform.tfstate` (versioned bucket, S3-native lock file). The state bucket was created once with the AWS CLI before the first `init`.

Content is deployed by syncing the site build into the `bucket` output and invalidating the `distribution_id` output.
