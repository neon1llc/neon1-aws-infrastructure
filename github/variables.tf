# github/variables.tf - Repositories, buckets, and IDs the roles are scoped to.


# Repositories whose main branches get roles
variable "github_org" {
  description = "GitHub organization that owns the repositories."
  type        = string
  default     = "neon1llc"
}


variable "site_repo" {
  description = "Repository whose main branch deploys the website."
  type        = string
  default     = "neon1-site"
}


variable "infra_repo" {
  description = "Repository whose main branch runs Terraform."
  type        = string
  default     = "neon1-aws-infrastructure"
}


# Terraform state, shared by every stack
variable "state_bucket" {
  description = "Bucket that holds Terraform state for every stack."
  type        = string
  default     = "neon1-tfstate"
}


# These match the site stack. Update them if the bucket or distribution is replaced
variable "site_bucket" {
  description = "Website origin bucket."
  type        = string
  default     = "neon1-public-website"
}


variable "site_distribution_id" {
  description = "CloudFront distribution in front of the website."
  type        = string
  default     = "EKL1R4AOR1VRG"
}


# The hosted zone the site stack writes records in
variable "zone_id" {
  description = "Route 53 hosted zone for neon1.tech."
  type        = string
  default     = "Z009089523ACQHD83TGQI"
}


# The 1NEON portal: its OIDC subject and app bucket. 1NEON uses GitHub's immutable
# subjects, so its tokens name the owner and repository by ID as well as by name
variable "portal_subject" {
  description = "OIDC subject prefix for the neon1-1NEON repository, without the repo: and :ref parts."
  type        = string
  default     = "neon1llc@226603321/neon1-1NEON@1448370069"
}


variable "portal_app_bucket" {
  description = "1NEON SPA bucket (created by the 1NEON stack)."
  type        = string
  default     = "neon1-1neon-app-prod"
}


# The neon1.tech assistant: its OIDC subject, by owner and repository ID as well as name
variable "chat_subject" {
  description = "OIDC subject prefix for the neon1-chat repository, without the repo: and :ref parts."
  type        = string
  default     = "neon1llc@226603321/neon1-chat@1450393950"
}


# The one account these stacks belong to. Given by the Makefile (from .expected-account locally, or
# the role ARN in CI) rather than written here, and checked by the provider before any change
variable "expected_account_id" {
  description = "The 12-digit AWS account ID this stack must run in."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "expected_account_id must be a 12-digit AWS account ID."
  }
}


# Generated IDs of the resources each role manages. Mutations are scoped to these; if one is ever
# recreated, its new ID goes here (creating a replacement is allowed, changing others is not)
variable "portal_user_pool_id" {
  description = "1NEON's Cognito user pool."
  type        = string
  default     = "us-east-1_C8Tl1RRPe"
}

variable "portal_api_id" {
  description = "1NEON's HTTP API."
  type        = string
  default     = "rqe8xwws41"
}

variable "chat_api_id" {
  description = "The neon1.tech assistant's HTTP API."
  type        = string
  default     = "n3ju67jjrd"
}

# The assistant's model, matching neon1-chat's own model variable (without any "us." prefix)
variable "portal_neo_model_id" {
  description = "Bedrock model ID 1NEON's Neo may call."
  type        = string
  default     = "anthropic.claude-sonnet-5-5"
}

variable "chat_model_id" {
  description = "Bedrock model ID the assistant may call."
  type        = string
  default     = "qwen.qwen3-next-80b-a3b"
}
