resource "aws_security_group" "alb_sg" {
  name        = "depi-sec-alb-sg"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.app_vpc.id

  tags = {
    Name = "depi-sec-alb-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_out" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "app_sg" {
  name        = "depi-sec-app-sg"
  description = "Security group for App instances"
  vpc_id      = aws_vpc.app_vpc.id

  tags = {
    Name = "depi-sec-app-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_http" {
  security_group_id            = aws_security_group.app_sg.id
  referenced_security_group_id = aws_security_group.alb_sg.id
  from_port                    = 80
  ip_protocol                  = "tcp"
  to_port                      = 80
}

resource "aws_vpc_security_group_egress_rule" "app_out" {
  security_group_id = aws_security_group.app_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "db_sg" {
  name        = "depi-sec-db-sg"
  description = "Security group for RDS"
  vpc_id      = aws_vpc.app_vpc.id

  tags = {
    Name = "depi-sec-db-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "db_mysql" {
  security_group_id            = aws_security_group.db_sg.id
  referenced_security_group_id = aws_security_group.app_sg.id
  from_port                    = 3306
  ip_protocol                  = "tcp"
  to_port                      = 3306
}

resource "aws_vpc_security_group_egress_rule" "db_out" {
  security_group_id = aws_security_group.db_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "efs_sg" {
  name        = "depi-sec-efs-sg"
  description = "Security group for EFS"
  vpc_id      = aws_vpc.app_vpc.id

  tags = {
    Name = "depi-sec-efs-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "efs_nfs" {
  security_group_id            = aws_security_group.efs_sg.id
  referenced_security_group_id = aws_security_group.app_sg.id
  from_port                    = 2049
  ip_protocol                  = "tcp"
  to_port                      = 2049
}

resource "aws_vpc_security_group_egress_rule" "efs_out" {
  security_group_id = aws_security_group.efs_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
