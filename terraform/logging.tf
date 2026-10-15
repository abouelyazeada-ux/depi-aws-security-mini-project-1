# ==============================================================================
# Task 14: AWS CloudTrail & CloudWatch Logs Integration
# ==============================================================================

# CloudWatch Log Group for CloudTrail log events (14-day retention)
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/depi-sec-trail"
  retention_in_days = 14
}

# IAM Role assumed by CloudTrail service to publish logs to CloudWatch Logs
resource "aws_iam_role" "cloudtrail_cw_role" {
  name = "depi-sec-cloudtrail-cw-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudTrailAssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Least-privilege IAM Policy allowing CloudTrail to create streams and put log events
resource "aws_iam_role_policy" "cloudtrail_cw_policy" {
  name = "depi-sec-cloudtrail-cw-policy"
  role = aws_iam_role.cloudtrail_cw_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailCreateLogStream"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
        ]
      },
      {
        Sid    = "AWSCloudTrailPutLogEvents"
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
        ]
      }
    ]
  })
}

# Multi-region CloudTrail with log validation, management events, and S3 read data events
resource "aws_cloudtrail" "trail" {
  name                          = "depi-sec-trail"
  s3_bucket_name                = aws_s3_bucket.logs_bucket.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cw_role.arn

  # Management events: Read and Write (All)
  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  # Data events: S3 object-level Read events ONLY for the application bucket
  event_selector {
    read_write_type           = "ReadOnly"
    include_management_events = false

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.app_bucket.arn}/"]
    }
  }

  depends_on = [
    aws_s3_bucket_policy.logs_bucket_policy,
    aws_iam_role_policy.cloudtrail_cw_policy
  ]
}
