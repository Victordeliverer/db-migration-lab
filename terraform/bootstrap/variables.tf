variable "state_bucket_name" {
  description = "Globally-unique S3 bucket name for Terraform remote state."
  type        = string
  default     = "victor-db-migration-lab-tfstate"
}

variable "expiry_tag" {
  description = "Date this lab environment should be torn down (informational tag, not enforced)."
  type        = string
  default     = "2026-10-31"
}
