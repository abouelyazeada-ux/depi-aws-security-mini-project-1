resource "aws_iam_account_password_policy" "strict" {
  minimum_password_length      = 14
  require_uppercase_characters = true
  require_lowercase_characters = true
  require_numbers              = true
  require_symbols              = true
  max_password_age             = 90
}

resource "aws_iam_group" "developers" {
  name = "depi-sec-developers"
}

resource "aws_iam_group_policy_attachment" "developers_readonly" {
  group      = aws_iam_group.developers.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_user" "dev1" {
  name = "depi-dev-1"
}

resource "aws_iam_user_group_membership" "dev1_group" {
  user   = aws_iam_user.dev1.name
  groups = [aws_iam_group.developers.name]
}

resource "aws_iam_user_login_profile" "dev1_login" {
  user                    = aws_iam_user.dev1.name
  password_reset_required = true
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

locals {
  app_bucket_name = "depi-sec-app-${random_id.bucket_suffix.hex}"
}

resource "aws_iam_policy" "s3_app_read" {
  name        = "depi-sec-s3-app-read"
  description = "Allows s3:GetObject on the application bucket"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "arn:aws:s3:::${local.app_bucket_name}/*"
      }
    ]
  })
}

resource "aws_iam_role" "ec2_role" {
  name = "depi-sec-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_s3_read" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_app_read.arn
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "depi-sec-ec2-role"
  role = aws_iam_role.ec2_role.name
}
