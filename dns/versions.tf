# dns/versions.tf - Terraform and provider versions, remote state, and the AWS provider.


# Remote state lives in the neon1-tfstate bucket (versioned); S3-native locking
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
    key          = "dns/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}


# Credentials come from AWS_PROFILE / the environment, never hardcoded.
# Route 53 is global; us-east-1 matches the other stacks
provider "aws" {
  region = "us-east-1"
  # Refuse to plan or apply against any account but the expected one
  allowed_account_ids = [var.expected_account_id]

  default_tags {
    tags = {
      Project   = "neon1-dns"
      ManagedBy = "terraform"
    }
  }
}
