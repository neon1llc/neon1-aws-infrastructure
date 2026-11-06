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

variable "state_bucket" {
  description = "Bucket that holds Terraform state for every stack."
  type        = string
  default     = "neon1-tfstate"
}

# These match the site stack. Update them if the bucket or distribution is replaced.
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

variable "zone_id" {
  description = "Route 53 hosted zone for neon1.tech."
  type        = string
  default     = "Z009089523ACQHD83TGQI"
}

variable "portal_repo" {
  description = "Repository for the 1NEON portal (app and its own Terraform)."
  type        = string
  default     = "1NEON"
}

variable "portal_app_bucket" {
  description = "1NEON SPA bucket (created by the 1NEON stack)."
  type        = string
  default     = "neon1-1neon-app-prod"
}
