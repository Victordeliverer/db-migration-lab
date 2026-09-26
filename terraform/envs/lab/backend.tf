terraform {
  backend "s3" {
    bucket       = "victor-db-migration-lab-tfstate"
    key          = "envs/lab/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true # S3-native locking — no DynamoDB table needed
  }
}
