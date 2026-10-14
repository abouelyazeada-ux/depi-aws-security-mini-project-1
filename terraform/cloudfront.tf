resource "random_password" "origin_verify_header" {
  length  = 32
  special = false
}

resource "aws_cloudfront_distribution" "cf" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "depi-sec-cloudfront"
  price_class     = "PriceClass_100"

  origin {
    domain_name = aws_lb.alb.dns_name
    origin_id   = "depi-sec-alb"

    custom_header {
      name  = "X-Origin-Verify"
      value = random_password.origin_verify_header.result
    }

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "depi-sec-alb"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "depi-sec-cloudfront"
  }
}

# --- CloudFront Standard Logging v2 ---

resource "aws_cloudwatch_log_delivery_source" "cf_source" {
  name         = "depi-sec-cf-access-logs-source"
  log_type     = "ACCESS_LOGS"
  resource_arn = aws_cloudfront_distribution.cf.arn
}

resource "aws_cloudwatch_log_delivery_destination" "s3_destination" {
  name          = "depi-sec-cf-s3-destination"
  output_format = "json"

  delivery_destination_configuration {
    destination_resource_arn = aws_s3_bucket.logs_bucket.arn
  }
}

resource "aws_cloudwatch_log_delivery" "cf_delivery" {
  delivery_source_name     = aws_cloudwatch_log_delivery_source.cf_source.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.s3_destination.arn

  depends_on = [
    aws_s3_bucket_policy.logs_bucket_policy
  ]
}
