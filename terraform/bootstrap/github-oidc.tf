# ---------------------------------------------------------------------------
# GitHub Actions OIDC: lets CI authenticate to AWS with short-lived,
# auto-rotating credentials — no long-lived AWS access keys stored as
# GitHub secrets, ever. This is the single biggest "shows real platform
# maturity" item in the whole CI setup.
#
# How it works: GitHub's OIDC provider issues a signed token for each
# workflow run. AWS trusts that token (via the identity provider below)
# and lets the workflow assume an IAM role, scoped to this exact repo.
# ---------------------------------------------------------------------------

variable "github_repository" {
  description = "GitHub repo in 'owner/name' form, for the OIDC trust condition."
  type        = string
  default     = "Victordeliverer/db-migration-lab"
}

# GitHub's OIDC thumbprint is stable and documented by GitHub/AWS; the
# provider block still requires one. AWS validates the token signature
# via its cached intermediate CAs regardless, but the argument is required.
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]

  tags = { Name = "github-actions-oidc" }
}

# ---------------------------------------------------------------------------
# IAM role CI assumes. Trust policy is scoped to:
#   - THIS repo only (no other repo, even in the same GitHub org, can assume it)
#   - both pull_request runs (plan on PRs) and pushes to main (plan/apply on merge)
# Tighten further later (Day 6 IAM review) if you want branch-specific rules.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "github_actions_ci" {
  name = "db-migration-lab-github-ci"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:*"
          }
        }
      }
    ]
  })

  tags = { Name = "db-migration-lab-github-ci" }
}

# ---------------------------------------------------------------------------
# Permissions: read-only across AWS (for `terraform plan` to see current
# state of everything), PLUS explicit read/write on just the state bucket
# path this env uses (S3-native locking needs PutObject/DeleteObject to
# acquire/release the lock, not just GetObject) and KMS decrypt for that
# bucket's encryption key. This is read-only for actual infrastructure —
# CI can plan, never apply, until you deliberately widen this.
# ---------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "ci_read_only" {
  role       = aws_iam_role.github_actions_ci.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "ci_state_access" {
  name = "db-migration-lab-ci-state-access"
  role = aws_iam_role.github_actions_ci.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StateBucketListAndLock"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.tfstate.arn
      },
      {
        Sid    = "StateObjectReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.tfstate.arn}/envs/lab/*"
      },
      {
        Sid    = "StateKmsAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.tfstate.arn
      }
    ]
  })
}

output "github_ci_role_arn" {
  description = "Paste into the GitHub repo variable AWS_CI_ROLE_ARN, used by the workflow."
  value       = aws_iam_role.github_actions_ci.arn
}

