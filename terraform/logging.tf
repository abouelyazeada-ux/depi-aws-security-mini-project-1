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

# ==============================================================================
# Task 15: VPC Flow Logs & CloudWatch Logs Integration
# ==============================================================================

# CloudWatch Log Group for VPC Flow Logs (14-day retention)
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/depi-sec/vpc/flowlogs"
  retention_in_days = 14
}

# IAM Role assumed by VPC Flow Logs service to publish logs to CloudWatch Logs
resource "aws_iam_role" "vpc_flow_logs_role" {
  name = "depi-sec-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VPCFlowLogsAssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Least-privilege IAM Policy for VPC Flow Logs CloudWatch publishing
# logs:CreateLogStream, logs:PutLogEvents, and logs:DescribeLogStreams are strictly scoped
# to the destination CloudWatch Log Group and its log streams.
# logs:DescribeLogGroups requires Resource = "*" because AWS IAM does not support
# resource-level ARN constraints for CloudWatch Logs DescribeLogGroups API operations.
resource "aws_iam_role_policy" "vpc_flow_logs_policy" {
  name = "depi-sec-vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VPCFlowLogsScopedGroupAndStreamActions"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          aws_cloudwatch_log_group.vpc_flow_logs.arn,
          "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
        ]
      },
      {
        Sid    = "VPCFlowLogsDescribeLogGroups"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# VPC Flow Log capturing ALL traffic on the application VPC
resource "aws_flow_log" "app_vpc_flow_log" {
  iam_role_arn         = aws_iam_role.vpc_flow_logs_role.arn
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs.arn
  log_destination_type = "cloud-watch-logs"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.app_vpc.id

  tags = {
    Name = "depi-sec-vpc-flow-log"
  }

  depends_on = [
    aws_iam_role_policy.vpc_flow_logs_policy
  ]
}
