# site/variables.tf - The domain, its zone, and the origin bucket.


# The apex domain and its hosted zone
variable "domain" {
  description = "Apex domain served by the site."
  type        = string
  default     = "neon1.tech"
}


variable "zone_id" {
  description = "Existing Route 53 hosted zone for the domain (read-only here)."
  type        = string
  default     = "Z009089523ACQHD83TGQI"
}


# The private origin bucket for the site
variable "bucket_name" {
  description = "Private S3 origin bucket."
  type        = string
  default     = "neon1-public-website"
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
