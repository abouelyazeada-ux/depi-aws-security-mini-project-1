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

output "tools_vpc_id" {
  description = "ID of the Tools VPC"
  value       = aws_vpc.tools_vpc.id
}

output "peering_connection_id" {
  description = "ID of the VPC peering connection between App VPC and Tools VPC"
  value       = aws_vpc_peering_connection.peering.id
}

output "tools_instance_id" {
  description = "Instance ID of the Tools monitoring EC2 instance"
  value       = aws_instance.tools_instance.id
}

output "tools_instance_private_ip" {
  description = "Private IP address of the Tools monitoring EC2 instance"
  value       = aws_instance.tools_instance.private_ip
}

output "backup_vault_name" {
  description = "Name of the AWS Backup vault"
  value       = aws_backup_vault.backup_vault.name
}

output "backup_vault_arn" {
  description = "ARN of the AWS Backup vault"
  value       = aws_backup_vault.backup_vault.arn
}

output "backup_plan_id" {
  description = "ID of the AWS Backup plan"
  value       = aws_backup_plan.backup_plan.id
}
