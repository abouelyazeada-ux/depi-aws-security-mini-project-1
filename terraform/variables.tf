variable "project_name" {
  type        = string
  description = "Project name"
  default     = "depi-mini-project-1"
}

variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  type        = string
  description = "Application VPC CIDR"
  default     = "10.0.0.0/16"
}

variable "alert_email" {
  type        = string
  description = "Email address for alerts"
}