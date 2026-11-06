# github/outputs.tf - Role ARNs to set as repository variables in each repository.


# The GitHub OIDC provider every role trusts
output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}


# Set as AWS_DEPLOY_ROLE_ARN in neon1-site
output "site_deploy_role_arn" {
  value = aws_iam_role.site_deploy.arn
}


# Set as AWS_TERRAFORM_ROLE_ARN in neon1-aws-infrastructure
output "terraform_role_arn" {
  value = aws_iam_role.terraform.arn
}
