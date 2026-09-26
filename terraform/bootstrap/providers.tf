terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Bootstrap has no remote backend — it CREATES the backend everything
  # else will use. Its own state stays local (or you move it to this
  # same bucket manually, once, after the first apply — see README note
  # at the bottom of this file).
}

provider "aws" {
  region = "eu-west-1"

  default_tags {
    tags = {
      project     = "db-migration-lab"
      owner       = "victor"
      environment = "bootstrap"
    }
  }
}
