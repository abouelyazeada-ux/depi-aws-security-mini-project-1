resource "aws_security_group" "endpoint_sg" {
  name        = "depi-sec-endpoint-sg"
  description = "Security group for VPC Endpoints"
  vpc_id      = aws_vpc.app_vpc.id

  tags = {
    Name = "depi-sec-endpoint-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "endpoint_https" {
  security_group_id = aws_security_group.endpoint_sg.id
  cidr_ipv4         = "10.0.0.0/16"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "endpoint_out" {
  security_group_id = aws_security_group.endpoint_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_id            = aws_vpc.app_vpc.id
  service_name      = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private_rt.id]

  tags = {
    Name = "depi-sec-s3-endpoint"
  }
}

resource "aws_vpc_endpoint" "ssm_endpoint" {
  vpc_id              = aws_vpc.app_vpc.id
  service_name        = "com.amazonaws.us-east-1.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.endpoint_sg.id]

  tags = {
    Name = "depi-sec-ssm-endpoint"
  }
}

resource "aws_vpc_endpoint" "ssmmessages_endpoint" {
  vpc_id              = aws_vpc.app_vpc.id
  service_name        = "com.amazonaws.us-east-1.ssmmessages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.endpoint_sg.id]

  tags = {
    Name = "depi-sec-ssmmessages-endpoint"
  }
}

resource "aws_vpc_endpoint" "ec2messages_endpoint" {
  vpc_id              = aws_vpc.app_vpc.id
  service_name        = "com.amazonaws.us-east-1.ec2messages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.endpoint_sg.id]

  tags = {
    Name = "depi-sec-ec2messages-endpoint"
  }
}
