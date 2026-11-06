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

variable "bucket_name" {
  description = "Private S3 origin bucket."
  type        = string
  default     = "neon1-public-website"
}
