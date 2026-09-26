# ---------------------------------------------------------------------------
# KMS key: encrypts the state bucket. A dedicated key (not the AWS-managed
# aws/s3 default) means you control the key policy and can prove
# least-privilege access to state in evidence/interviews.
# ---------------------------------------------------------------------------
resource "aws_kms_key" "tfstate" {
  description             = "KMS key for Terraform remote state (db-migration-lab)"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name   = "db-migration-lab-tfstate-key"
    expiry = var.expiry_tag
  }
}

resource "aws_kms_alias" "tfstate" {
  name          = "alias/db-migration-lab-tfstate"
  target_key_id = aws_kms_key.tfstate.key_id
}

# ---------------------------------------------------------------------------
# S3 bucket: the remote state store itself.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name

  # Prevents `terraform destroy` from silently deleting state history.
  # Remove this deliberately during the final teardown (§13 of the plan).
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name   = "db-migration-lab-tfstate"
    expiry = var.expiry_tag
  }
}

# Versioning: every state write is a new object version, so a bad apply
# or accidental delete is always recoverable.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption at rest with the dedicated KMS key above.
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.tfstate.arn
    }
    bucket_key_enabled = true
  }
}

# Block every form of public access. State can contain sensitive values
# even with `sensitive = true` on outputs (that only redacts CLI/UI
# display, not the underlying state file) — see Day 3 note in the plan.
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Deny any non-TLS request to the bucket.
resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.tfstate.arn,
          "${aws_s3_bucket.tfstate.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
}

# Lifecycle: keep noncurrent state versions for 90 days, then expire.
# Balances "recoverable from a bad apply" against unbounded storage cost.
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {} # applies to all objects in the bucket

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}
