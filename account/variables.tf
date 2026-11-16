# account/variables.tf - The account, where alerts go, and the account-wide spending line.


# Checked by the provider; the Makefile passes it from EXPECTED_ACCOUNT
variable "expected_account_id" {
  description = "The only AWS account this stack may change (12 digits)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "expected_account_id must be a 12-digit AWS account ID."
  }
}


# Budget and cost anomaly emails
variable "alert_email" {
  description = "Where budget and cost anomaly alerts go."
  type        = string
  default     = "neon1llc@gmail.com"
}


# A normal month is a few dollars, so this catches anything unplanned, tagged or not
variable "monthly_budget_usd" {
  description = "Account-wide monthly spend that triggers an email (80% actual, 100% forecast)."
  type        = number
  default     = 15
}


# A cost anomaly at or above this many dollars sends the daily email
variable "anomaly_threshold_usd" {
  description = "Dollar impact at which AWS cost anomaly detection emails."
  type        = number
  default     = 5
}


# How long the audit trail is kept, and how long each file can't be deleted
variable "trail_days" {
  description = "Days each audit log file is kept before it expires."
  type        = number
  default     = 400
}

variable "trail_lock_days" {
  description = "Days each audit log file is locked against deletion (governance mode)."
  type        = number
  default     = 365
}
