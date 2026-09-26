variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "azs" {
  description = "Two Availability Zones to spread the private subnets across."
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs for the two private subnets, one per AZ."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "name_prefix" {
  description = "Prefix applied to resource names/tags."
  type        = string
  default     = "db-migration-lab"
}

variable "enable_flow_logs" {
  description = "Whether to enable VPC Flow Logs to CloudWatch. Costs a small amount; toggle off to save budget."
  type        = bool
  default     = false
}

variable "flow_log_retention_days" {
  description = "CloudWatch Logs retention for VPC Flow Logs, if enabled."
  type        = number
  default     = 14
}
