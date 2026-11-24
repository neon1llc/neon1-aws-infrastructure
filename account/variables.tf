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
  default     = 2
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

# Everyone who gets budget and anomaly emails
variable "alert_emails" {
  description = "Budget and cost anomaly recipients."
  type        = list(string)
  default     = ["neon1llc@gmail.com", "pradeep@neon1.tech"]
}

# Bedrock is the only service that has moved the bill in a day: one evaluation night cost about $30
variable "bedrock_daily_usd" {
  description = "Daily Bedrock spend that sends an email."
  type        = number
  default     = 1
}

variable "bedrock_monthly_usd" {
  description = "Monthly Bedrock spend at which model calls from the human admin user are denied. Ten keeps Bedrock and the rest of the account inside the $15 budget."
  type        = number
  default     = 10
}
