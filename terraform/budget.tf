# IAM Customer-Managed Policy to Deny Expensive Resources
resource "aws_iam_policy" "deny_expensive" {
  name        = "depi-sec-deny-expensive"
  description = "Deny EC2 and RDS instance creation when budget is exceeded"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Deny"
        Action = [
          "ec2:RunInstances",
          "rds:CreateDBInstance"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Role for AWS Budgets to assume
resource "aws_iam_role" "budgets_role" {
  name = "depi-sec-budgets-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "budgets.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach IAM permissions to the Budgets role so it can attach policies to groups
resource "aws_iam_role_policy" "budgets_policy" {
  name = "depi-sec-budgets-policy"
  role = aws_iam_role.budgets_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:AttachGroupPolicy"
        ]
        Resource = "*"
      }
    ]
  })
}

# AWS Monthly Budget
resource "aws_budgets_budget" "monthly" {
  name         = "depi-sec-monthly"
  budget_type  = "COST"
  limit_amount = "10.0"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}

# Budget Action at 90% ACTUAL
resource "aws_budgets_budget_action" "apply_deny_policy" {
  budget_name        = aws_budgets_budget.monthly.name
  action_type        = "APPLY_IAM_POLICY"
  approval_model     = "AUTOMATIC"
  execution_role_arn = aws_iam_role.budgets_role.arn
  notification_type  = "ACTUAL"

  action_threshold {
    action_threshold_type  = "PERCENTAGE"
    action_threshold_value = 90
  }

  definition {
    iam_action_definition {
      policy_arn = aws_iam_policy.deny_expensive.arn
      groups     = [aws_iam_group.developers.name]
    }
  }

  subscriber {
    address           = var.alert_email
    subscription_type = "EMAIL"
  }
}
