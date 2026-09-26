# ---------------------------------------------------------------------------
# AWS Budget: alerts at 50%, 80%, 100% of a $15/month threshold for the
# whole lab. Lives in bootstrap (not envs/lab) because it should exist
# before anything else is created, and it protects the account as a whole,
# not just one environment.
#
# Note: AWS Budgets is a GLOBAL service (billing data is consolidated in
# us-east-1 regardless of where resources run), but the resource itself
# can be created from any provider region — no separate provider alias
# needed here.
# ---------------------------------------------------------------------------

variable "budget_monthly_limit_usd" {
  description = "Monthly cost threshold in USD for the lab budget alert."
  type        = string
  default     = "15"
}

variable "budget_alert_email" {
  description = "Email address to receive budget threshold alerts."
  type        = string
  default     = "deliverervictor@gmail.com"
}

resource "aws_budgets_budget" "lab_monthly" {
  name         = "db-migration-lab-monthly"
  budget_type  = "COST"
  limit_amount = var.budget_monthly_limit_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:project$db-migration-lab"]
  }

  # Warn early — 50% actual spend
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  # 80% actual spend
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  # 100% actual spend — you're over budget
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  # 100% FORECASTED — warns you before you actually hit the limit, based on
  # current spend trajectory. This is the one that catches "Aurora + DMS
  # left running over a long weekend" before it becomes a real overage.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
