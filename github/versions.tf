# github/versions.tf - Terraform and provider versions, remote state, and the AWS provider.


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
    key          = "github/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}


# Credentials come from AWS_PROFILE / the environment, never hardcoded
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "neon1-github"
      ManagedBy = "terraform"
    }
  }
}
