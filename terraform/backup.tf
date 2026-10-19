resource "aws_iam_role" "backup_role" {
  name = "depi-sec-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "depi-sec-backup-role"
  }
}

resource "aws_iam_role_policy_attachment" "backup_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
  role       = aws_iam_role.backup_role.name
}

resource "aws_iam_role_policy_attachment" "restore_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
  role       = aws_iam_role.backup_role.name
}

resource "aws_backup_vault" "backup_vault" {
  name = "depi-sec-vault"

  tags = {
    Name = "depi-sec-vault"
  }
}

# Vault Lock in Governance Mode (changeable_for_days intentionally omitted)
resource "aws_backup_vault_lock_configuration" "vault_lock" {
  backup_vault_name  = aws_backup_vault.backup_vault.name
  min_retention_days = 7
  max_retention_days = 365
}

resource "aws_backup_plan" "backup_plan" {
  name = "depi-sec-backup-plan"

  rule {
    rule_name         = "depi-sec-daily-backup-rule"
    target_vault_name = aws_backup_vault.backup_vault.name
    schedule          = "cron(0 5 * * ? *)"
    start_window      = 60
    completion_window = 120

    lifecycle {
      delete_after = 30
    }
  }

  tags = {
    Name = "depi-sec-backup-plan"
  }
}

resource "aws_backup_selection" "backup_selection" {
  name         = "depi-sec-backup-selection"
  plan_id      = aws_backup_plan.backup_plan.id
  iam_role_arn = aws_iam_role.backup_role.arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Project"
    value = "depi-mini-project-1"
  }
}
