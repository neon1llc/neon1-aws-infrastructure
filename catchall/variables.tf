# catchall/variables.tf - The domain, its zone, and the one account this stack belongs to.


variable "domain" {
  description = "Apex domain; the catch-all serves *.<domain>."
  type        = string
  default     = "neon1.tech"
}


variable "zone_id" {
  description = "Existing Route 53 hosted zone for the domain (read-only here)."
  type        = string
  default     = "Z009089523ACQHD83TGQI"
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
