# ==============================================================================
# Task 17: Event-Driven Security Auto-Remediation (Lambda & EventBridge)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Lambda Packaging & Log Group
# ------------------------------------------------------------------------------

# Package Python remediation function source code into a ZIP deployment archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/auto_remediate.py"
  output_path = "${path.module}/lambda/auto_remediate.zip"
}

# Dedicated CloudWatch Log Group with 14-day retention for Lambda execution logs
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/depi-sec-auto-remediation"
  retention_in_days = 14

  tags = {
    Name = "/aws/lambda/depi-sec-auto-remediation"
  }
}

# ------------------------------------------------------------------------------
# 2. IAM Execution Role & Least-Privilege Remediation Policy
# ------------------------------------------------------------------------------

# IAM Role assumed by AWS Lambda execution environment
resource "aws_iam_role" "lambda_remediation_role" {
  name = "depi-sec-lambda-remediation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaAssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "depi-sec-lambda-remediation-role"
  }
}

# Least-Privilege IAM Policy for Lambda Auto-Remediation:
# - ec2:DescribeSecurityGroups: Required to inspect ingress rules (Resource: *)
# - ec2:RevokeSecurityGroupIngress: Scoped strictly to the target application security group
# - sns:Publish: Scoped strictly to the platform alerts SNS topic
# - CloudWatch Logs: Scoped strictly to the function's dedicated log group
resource "aws_iam_role_policy" "lambda_remediation_policy" {
  name = "depi-sec-lambda-remediation-policy"
  role = aws_iam_role.lambda_remediation_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2DescribeSecurityGroups"
        Effect = "Allow"
        Action = [
          "ec2:DescribeSecurityGroups"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2RevokeSecurityGroupIngress"
        Effect = "Allow"
        Action = [
          "ec2:RevokeSecurityGroupIngress"
        ]
        Resource = aws_security_group.app_sg.arn
      },
      {
        Sid    = "SNSPublishAlerts"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.alerts.arn
      },
      {
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.lambda_logs.arn}:*"
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# 3. AWS Lambda Function
# ------------------------------------------------------------------------------

# Python 3.12 Lambda function for automated security group rule remediation
resource "aws_lambda_function" "auto_remediate" {
  function_name    = "depi-sec-auto-remediation"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  role             = aws_iam_role.lambda_remediation_role.arn
  handler          = "auto_remediate.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      SNS_TOPIC_ARN            = aws_sns_topic.alerts.arn
      TARGET_SECURITY_GROUP_ID = aws_security_group.app_sg.id
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
    aws_iam_role_policy.lambda_remediation_policy
  ]

  tags = {
    Name = "depi-sec-auto-remediation"
  }
}

# ------------------------------------------------------------------------------
# 4. Amazon EventBridge Rule, Target, and Lambda Invocation Permission
# ------------------------------------------------------------------------------

# EventBridge rule matching CloudTrail AuthorizeSecurityGroupIngress API calls
resource "aws_cloudwatch_event_rule" "remediate_open_ssh" {
  name        = "depi-sec-remediate-open-ssh"
  description = "Triggers auto-remediation Lambda when AuthorizeSecurityGroupIngress is called"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["ec2.amazonaws.com"]
      eventName   = ["AuthorizeSecurityGroupIngress"]
    }
  })

  tags = {
    Name = "depi-sec-remediate-open-ssh"
  }
}

# Target binding EventBridge rule to the Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.remediate_open_ssh.name
  target_id = "AutoRemediateOpenSSH"
  arn       = aws_lambda_function.auto_remediate.arn
}

# Resource-based policy allowing EventBridge service principal to invoke the Lambda function
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auto_remediate.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.remediate_open_ssh.arn
}
