# dns/variables.tf - The domain, its zone, and the values its shared records carry.


# The apex domain and its hosted zone (owned outside these stacks)
variable "domain" {
  description = "Apex domain whose shared records this stack manages."
  type        = string
  default     = "neon1.tech"
}


variable "zone_id" {
  description = "Existing Route 53 hosted zone for the domain."
  type        = string
  default     = "Z009089523ACQHD83TGQI"
}


# The SOA's primary name server (Route 53 assigns it) and a dated serial, YYYYMMDDnn
variable "primary_name_server" {
  description = "The zone's primary name server, as Route 53 put it in the SOA."
  type        = string
  default     = "ns-721.awsdns-26.net."
}


variable "soa_serial" {
  description = "SOA serial in YYYYMMDDnn form."
  type        = number
  default     = 2026111101

  validation {
    condition     = var.soa_serial >= 2026010100 && var.soa_serial < 2100010100
    error_message = "soa_serial must be a date in YYYYMMDDnn form."
  }
}


# Google Workspace receives and sends mail for the apex
variable "google_site_verification" {
  description = "Google Workspace domain verification token."
  type        = string
  default     = "5AEODCMluloRcJtrnyCdD02-Z2eC8NBMg5VH1NvOfRA"
}


# The public half of Google Workspace's DKIM key (Admin console > Gmail > Authenticate email)
variable "google_dkim_public_key" {
  description = "Base64 public key for the google._domainkey selector."
  type        = string
  default     = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA4gsuVvlHn3e35laL5ZDy7mXLs1PKdGo70TgXJ5iq0+tWXRA3aQxBnTEPr+p2kU51ZC9kzEhweLZCfqiTTITfavujQ/Y4O3L+LiaBTdIwbtsNw5j5FiM2Z9CKU5t8d4xwxlnvzByFg9tbZ78Hv6MIj8HpFfBFkFQI7HmW+hvCS2bkCHqZWbno7anqVC0itO7e290zN1VW2wxgCz3mvL4fvxs0YHfu5zcF5W0+IznepM3md4NmI6I/aLLjihCXTnHUToTgzVC524xS7hkx+0AX+Y9rRpHKR1SLWeBKTt12GUZt/gxlGDrKzDb5fVMGHLFBiicQT9CYxp2g4tNQl31MGQIDAQAB"
}


# What receivers do with mail that fails DMARC. Moves none -> quarantine -> reject as reports stay clean
variable "dmarc_policy" {
  description = "DMARC policy for the apex and its subdomains: none, quarantine, or reject."
  type        = string
  default     = "quarantine"

  validation {
    condition     = contains(["none", "quarantine", "reject"], var.dmarc_policy)
    error_message = "dmarc_policy must be none, quarantine, or reject."
  }
}


# MTA-STS policy version: change it (a date is fine) whenever neon1-site's mta-sts.txt changes
variable "mta_sts_id" {
  description = "MTA-STS policy id, 1 to 32 letters and digits."
  type        = string
  default     = "20261111"

  validation {
    condition     = can(regex("^[A-Za-z0-9]{1,32}$", var.mta_sts_id))
    error_message = "mta_sts_id must be 1 to 32 letters and digits."
  }
}


# Where DNSSEC alarms go: 1NEON's alerts topic, in this account and region
variable "alerts_topic_name" {
  description = "Existing SNS topic that receives the DNSSEC alarms."
  type        = string
  default     = "1neon-prod-alerts"
}


# BIMI logo (SVG Tiny PS over HTTPS) and, once bought, its mark certificate. Empty leaves BIMI off
variable "bimi_logo_url" {
  description = "HTTPS URL of the SVG Tiny PS brand logo, or empty for no BIMI record."
  type        = string
  default     = "https://neon1.tech/bimi/neon1.svg"
}


variable "bimi_authority_url" {
  description = "HTTPS URL of a VMC or CMC certificate (PEM), or empty for a self-asserted logo."
  type        = string
  default     = ""
}


# The one account these stacks belong to, given by the Makefile and checked by the provider
variable "expected_account_id" {
  description = "The 12-digit AWS account ID this stack must run in."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "expected_account_id must be a 12-digit AWS account ID."
  }
}
