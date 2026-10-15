# ==============================================================================
# Task 16: CloudWatch Alarms & Operations Dashboard
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Amazon SNS Alert Topic & Permissions
# ------------------------------------------------------------------------------

# Amazon SNS Topic for platform alerts
# Encryption Decision:
# Amazon SNS server-side encryption with AWS managed key (alias/aws/sns) is incompatible
# with Amazon CloudWatch Alarms publishing because the default AWS KMS key policy
# cannot be modified to grant kms:GenerateDataKey and kms:Decrypt permissions to the
# CloudWatch service principal (cloudwatch.amazonaws.com). To enable SSE on this topic
# without blocking alarm delivery, a Customer Managed Key (CMK) would be required,
# which incurs an additional $1.00/month charge (10% of the project's $10 budget).
# Therefore, the topic is maintained without KMS encryption, and access is strictly
# guarded by a least-privilege SNS Topic Policy allowing only the CloudWatch Alarms
# service within this AWS account to publish.
resource "aws_sns_topic" "alerts" {
  name = "depi-sec-alerts"

  tags = {
    Name = "depi-sec-alerts"
  }
}

# Least-privilege SNS Topic Policy:
# 1. Grants the owning AWS account permissions to administer, subscribe, and publish to the topic.
# 2. Grants CloudWatch Alarms service principal publishing rights, strictly scoped to this AWS account.
resource "aws_sns_topic_policy" "alerts_policy" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountOwnerManageTopic"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "sns:GetTopicAttributes",
          "sns:SetTopicAttributes",
          "sns:AddPermission",
          "sns:RemovePermission",
          "sns:DeleteTopic",
          "sns:Subscribe",
          "sns:ListSubscriptionsByTopic",
          "sns:Publish"
        ]
        Resource = aws_sns_topic.alerts.arn
      },
      {
        Sid    = "AllowCloudWatchAlarmsPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# SNS Email Subscription for administrator alerts
resource "aws_sns_topic_subscription" "email_alerts" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ------------------------------------------------------------------------------
# 2. Alarm 1: EC2 CPU Utilization (> 70% for 2 consecutive 5-min periods)
# ------------------------------------------------------------------------------

# Monitor application EC2 instances app-a and app-b independently
resource "aws_cloudwatch_metric_alarm" "ec2_cpu_high" {
  for_each = {
    "app-a" = aws_instance.app_a.id
    "app-b" = aws_instance.app_b.id
  }

  alarm_name          = "depi-sec-ec2-cpu-high-${each.key}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "EC2 CPU utilization exceeded 70% for 2 consecutive 5-minute periods on ${each.key}"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = each.value
  }

  tags = {
    Name = "depi-sec-ec2-cpu-high-${each.key}"
  }
}

# ------------------------------------------------------------------------------
# 3. Alarm 2: ALB UnHealthy Target Hosts (> 0)
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name          = "depi-sec-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "One or more targets in depi-sec-tg are unhealthy on depi-sec-alb"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.alb.arn_suffix
    TargetGroup  = aws_lb_target_group.app_tg.arn_suffix
  }

  tags = {
    Name = "depi-sec-alb-unhealthy-hosts"
  }
}

# ------------------------------------------------------------------------------
# 4. Alarm 3: RDS Low Free Storage Space (< 2 GB)
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "rds_free_storage_low" {
  alarm_name          = "depi-sec-rds-free-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 2147483648 # 2 GB in Bytes (2 * 1024 * 1024 * 1024)
  alarm_description   = "RDS MySQL free storage space dropped below 2 GB on depi-sec-db"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.db.identifier
  }

  tags = {
    Name = "depi-sec-rds-free-storage-low"
  }
}

# ------------------------------------------------------------------------------
# 5. Alarm 4: Security - CloudTrail Failed Console Logins (>= 3 in 5 minutes)
# ------------------------------------------------------------------------------

# Metric Filter on CloudTrail log group targeting Failed Authentication events
resource "aws_cloudwatch_log_metric_filter" "failed_console_logins" {
  name           = "depi-sec-failed-console-logins-filter"
  pattern        = "{ ($.eventName = \"ConsoleLogin\") && ($.errorMessage = \"Failed authentication\") }"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name

  metric_transformation {
    name          = "FailedConsoleLogins"
    namespace     = "depi-sec/Security"
    value         = "1"
    default_value = 0
  }
}

# Metric Alarm firing when 3 or more failed console logins occur within 5 minutes
resource "aws_cloudwatch_metric_alarm" "failed_console_logins" {
  alarm_name          = "depi-sec-failed-console-logins-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.failed_console_logins.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.failed_console_logins.metric_transformation[0].namespace
  period              = 300
  statistic           = "Sum"
  threshold           = 3
  alarm_description   = "Security Alert: 3 or more failed AWS Management Console logins detected within 5 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = {
    Name = "depi-sec-failed-console-logins-alarm"
  }
}

# ------------------------------------------------------------------------------
# 6. CloudWatch Dashboard: depi-sec-overview
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "overview" {
  dashboard_name = "depi-sec-overview"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.app_a.id, { label = "depi-sec-app-a CPU", color = "#1f77b4" }],
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.app_b.id, { label = "depi-sec-app-b CPU", color = "#aec7e8" }]
          ]
          period = 300
          stat   = "Average"
          region = var.region
          title  = "EC2 Compute CPU Utilization (%)"
          yAxis  = { left = { min = 0, max = 100 } }
          annotations = {
            horizontal = [
              { value = 70, label = "Threshold (70%)", color = "#d62728" }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", aws_lb_target_group.app_tg.arn_suffix, "LoadBalancer", aws_lb.alb.arn_suffix, { label = "Unhealthy Targets", color = "#d62728" }]
          ]
          period = 60
          stat   = "Maximum"
          region = var.region
          title  = "ALB Target Group UnHealthy Hosts"
          yAxis  = { left = { min = 0 } }
          annotations = {
            horizontal = [
              { value = 0, label = "Threshold (> 0)", color = "#d62728" }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", aws_db_instance.db.identifier, { label = "RDS Available Storage (Bytes)", color = "#2ca02c" }]
          ]
          period = 300
          stat   = "Average"
          region = var.region
          title  = "RDS Database Free Storage Space"
          annotations = {
            horizontal = [
              { value = 2147483648, label = "Threshold (2 GB)", color = "#d62728" }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["depi-sec/Security", "FailedConsoleLogins", { label = "Console Auth Failures", color = "#ff7f0e" }]
          ]
          period = 300
          stat   = "Sum"
          region = var.region
          title  = "Security: CloudTrail Failed Console Logins"
          yAxis  = { left = { min = 0 } }
          annotations = {
            horizontal = [
              { value = 3, label = "Threshold (>= 3)", color = "#d62728" }
            ]
          }
        }
      }
    ]
  })
}
