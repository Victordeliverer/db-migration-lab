terraform {
  required_version = ">= 1.10.0" # required for use_lockfile in the S3 backend

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = "eu-west-1"

  default_tags {
    tags = {
      project     = "db-migration-lab"
      owner       = "victor"
      environment = "lab"
    }
  }
}
