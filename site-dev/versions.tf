# site-dev/versions.tf - Terraform and provider versions, remote state, and the AWS provider for
# dev.neon1.tech. Its own state, so nothing planned here can touch the live site's resources.


# Remote state in the neon1-tfstate bucket, beside the other stacks; S3-native locking
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "neon1-tfstate"
    key          = "site-dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}


# Credentials come from AWS_PROFILE / the environment; CloudFront needs us-east-1
provider "aws" {
  region              = "us-east-1"
  allowed_account_ids = [var.expected_account_id]

  default_tags {
    tags = {
      Project     = "neon1-site"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}
