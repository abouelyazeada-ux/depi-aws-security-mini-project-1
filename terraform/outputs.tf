output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.alb.dns_name
}

output "rds_endpoint" {
  description = "Connection endpoint for the RDS MySQL instance"
  value       = aws_db_instance.db.endpoint
}

output "rds_address" {
  description = "Hostname of the RDS MySQL instance"
  value       = aws_db_instance.db.address
}

output "rds_port" {
  description = "Port of the RDS MySQL instance"
  value       = aws_db_instance.db.port
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret storing database credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.cf.domain_name
}
