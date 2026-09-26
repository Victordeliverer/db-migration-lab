output "state_bucket_name" {
  description = "S3 bucket to reference in terraform/envs/lab/backend.tf"
  value       = aws_s3_bucket.tfstate.id
}

output "state_bucket_arn" {
  value = aws_s3_bucket.tfstate.arn
}

output "kms_key_arn" {
  description = "KMS key ARN — reuse for state encryption and reference in IAM policies"
  value       = aws_kms_key.tfstate.arn
}
