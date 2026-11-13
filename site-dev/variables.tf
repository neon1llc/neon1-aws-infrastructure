# site-dev/variables.tf - The dev host, its zone, and whether the 1NEON dev backend is wired in.


# The apex domain; dev lives at dev.<domain>
variable "domain" {
  description = "Apex domain; the dev site is served at dev.<domain>."
  type        = string
  default     = "neon1.tech"
}


variable "zone_id" {
  description = "Existing Route 53 hosted zone for the domain (read-only here)."
  type        = string
  default     = "Z009089523ACQHD83TGQI"
}


# The private bucket dev releases are uploaded to
variable "bucket_name" {
  description = "Private S3 origin bucket for dev.neon1.tech."
  type        = string
  default     = "neon1-site-dev"
}


# On once neon1-1NEON's infra/envs/dev is applied: /1NEON and /1NEON/api then reach the dev
# backend it publishes under /1neon/dev/. Off, /1NEON on dev is a plain not-found
variable "portal" {
  description = "Route /1NEON to the 1NEON dev backend (apply neon1-1NEON infra/envs/dev first)."
  type        = bool
  default     = true
}


# The one account this stack belongs to, given by the Makefile and checked by the provider
variable "expected_account_id" {
  description = "The 12-digit AWS account ID this stack must run in."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "expected_account_id must be a 12-digit AWS account ID."
  }
}


# Where the dev budget alert goes
variable "alert_email" {
  type    = string
  default = "neon1llc@gmail.com"
}
