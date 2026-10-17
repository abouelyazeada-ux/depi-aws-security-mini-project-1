# Task 18 — VPC Peering & Tools VPC Infrastructure

resource "aws_vpc" "tools_vpc" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "depi-sec-tools-vpc"
  }
}

resource "aws_subnet" "tools_a" {
  vpc_id                  = aws_vpc.tools_vpc.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Name = "depi-sec-tools-a"
  }
}

resource "aws_vpc_peering_connection" "peering" {
  vpc_id      = aws_vpc.app_vpc.id
  peer_vpc_id = aws_vpc.tools_vpc.id
  auto_accept = true

  tags = {
    Name = "depi-sec-app-tools-peering"
  }
}

# Route in App VPC Private Route Table to Tools VPC via Peering
resource "aws_route" "app_private_to_tools" {
  route_table_id            = aws_route_table.private_rt.id
  destination_cidr_block    = "10.1.0.0/16"
  vpc_peering_connection_id = aws_vpc_peering_connection.peering.id
}

# Route Table for Tools VPC pointing to App VPC via Peering
resource "aws_route_table" "tools_rt" {
  vpc_id = aws_vpc.tools_vpc.id

  route {
    cidr_block                = "10.0.0.0/16"
    vpc_peering_connection_id = aws_vpc_peering_connection.peering.id
  }

  tags = {
    Name = "depi-sec-tools-rt"
  }
}

resource "aws_route_table_association" "tools_a_assoc" {
  subnet_id      = aws_subnet.tools_a.id
  route_table_id = aws_route_table.tools_rt.id
}

# Security Group for Tools Monitoring Instance
resource "aws_security_group" "tools_sg" {
  name        = "depi-sec-tools-sg"
  description = "Security group for tools monitoring instance"
  vpc_id      = aws_vpc.tools_vpc.id

  tags = {
    Name = "depi-sec-tools-sg"
  }
}

# Least-Privilege Outbound Rules on Tools Security Group
resource "aws_vpc_security_group_egress_rule" "tools_out_http_private_a" {
  security_group_id = aws_security_group.tools_sg.id
  cidr_ipv4         = aws_subnet.private_a.cidr_block
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "Allow outbound HTTP port 80 to app private subnet A"
}

resource "aws_vpc_security_group_egress_rule" "tools_out_http_private_b" {
  security_group_id = aws_security_group.tools_sg.id
  cidr_ipv4         = aws_subnet.private_b.cidr_block
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "Allow outbound HTTP port 80 to app private subnet B"
}

resource "aws_vpc_security_group_egress_rule" "tools_out_https_private_a" {
  security_group_id = aws_security_group.tools_sg.id
  cidr_ipv4         = aws_subnet.private_a.cidr_block
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "Allow outbound HTTPS port 443 to SSM endpoints in private subnet A"
}

resource "aws_vpc_security_group_egress_rule" "tools_out_https_private_b" {
  security_group_id = aws_security_group.tools_sg.id
  cidr_ipv4         = aws_subnet.private_b.cidr_block
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "Allow outbound HTTPS port 443 to SSM endpoints in private subnet B"
}

resource "aws_vpc_security_group_egress_rule" "tools_out_icmp_private_a" {
  security_group_id = aws_security_group.tools_sg.id
  cidr_ipv4         = aws_subnet.private_a.cidr_block
  from_port         = -1
  to_port           = -1
  ip_protocol       = "icmp"
  description       = "Allow outbound ICMP ping to app private subnet A"
}

resource "aws_vpc_security_group_egress_rule" "tools_out_icmp_private_b" {
  security_group_id = aws_security_group.tools_sg.id
  cidr_ipv4         = aws_subnet.private_b.cidr_block
  from_port         = -1
  to_port           = -1
  ip_protocol       = "icmp"
  description       = "Allow outbound ICMP ping to app private subnet B"
}

# Security Group Ingress Rules on Existing Groups in App VPC
resource "aws_vpc_security_group_ingress_rule" "app_http_from_tools" {
  security_group_id = aws_security_group.app_sg.id
  cidr_ipv4         = "10.1.1.0/24"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "Allow HTTP port 80 from tools monitoring subnet"
}

resource "aws_vpc_security_group_ingress_rule" "app_icmp_from_tools" {
  security_group_id = aws_security_group.app_sg.id
  cidr_ipv4         = "10.1.1.0/24"
  from_port         = -1
  to_port           = -1
  ip_protocol       = "icmp"
  description       = "Allow ICMP ping from tools monitoring subnet"
}

resource "aws_vpc_security_group_ingress_rule" "endpoint_https_from_tools" {
  security_group_id = aws_security_group.endpoint_sg.id
  cidr_ipv4         = "10.1.1.0/24"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "Allow HTTPS port 443 from tools monitoring subnet to SSM endpoints"
}

# Least-Privilege Stateless Network ACL Rules on depi-sec-private-nacl
resource "aws_network_acl_rule" "in_150_http" {
  network_acl_id = aws_network_acl.private_nacl.id
  rule_number    = 150
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.1.1.0/24"
  from_port      = 80
  to_port        = 80
}

resource "aws_network_acl_rule" "in_151_icmp" {
  network_acl_id = aws_network_acl.private_nacl.id
  rule_number    = 151
  egress         = false
  protocol       = "icmp"
  rule_action    = "allow"
  cidr_block     = "10.1.1.0/24"
  icmp_type      = -1
  icmp_code      = -1
}

resource "aws_network_acl_rule" "in_152_ssm" {
  network_acl_id = aws_network_acl.private_nacl.id
  rule_number    = 152
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.1.1.0/24"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "out_150_tools_ephemeral" {
  network_acl_id = aws_network_acl.private_nacl.id
  rule_number    = 150
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.1.1.0/24"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "out_151_tools_icmp" {
  network_acl_id = aws_network_acl.private_nacl.id
  rule_number    = 151
  egress         = true
  protocol       = "icmp"
  rule_action    = "allow"
  cidr_block     = "10.1.1.0/24"
  icmp_type      = -1
  icmp_code      = -1
}

# Tools Monitoring EC2 Instance
resource "aws_instance" "tools_instance" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.tools_a.id
  vpc_security_group_ids      = [aws_security_group.tools_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = false

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 20
  }

  user_data = <<-EOF
    #!/bin/bash

    # 1. Dynamic resolution of SSM interface endpoint private IPs via official VPCE DNS names
    SSM_VPCE="${aws_vpc_endpoint.ssm_endpoint.dns_entry[0].dns_name}"
    SSMMESSAGES_VPCE="${aws_vpc_endpoint.ssmmessages_endpoint.dns_entry[0].dns_name}"
    EC2MESSAGES_VPCE="${aws_vpc_endpoint.ec2messages_endpoint.dns_entry[0].dns_name}"

    resolve_ip() {
      local vpce_name="$1"
      local ip=""
      for attempt in 1 2 3 4 5; do
        ip=$(getent hosts "$vpce_name" 2>/dev/null | awk '{print $1}' | head -n 1)
        if [ -n "$ip" ]; then
          echo "$ip"
          return 0
        fi
        sleep 2
      done
      return 1
    }

    SSM_IP=$(resolve_ip "$SSM_VPCE")
    SSMMESSAGES_IP=$(resolve_ip "$SSMMESSAGES_VPCE")
    EC2MESSAGES_IP=$(resolve_ip "$EC2MESSAGES_VPCE")

    if [ -n "$SSM_IP" ] && [ -n "$SSMMESSAGES_IP" ] && [ -n "$EC2MESSAGES_IP" ]; then
      echo "$SSM_IP ssm.us-east-1.amazonaws.com" >> /etc/hosts
      echo "$SSMMESSAGES_IP ssmmessages.us-east-1.amazonaws.com" >> /etc/hosts
      echo "$EC2MESSAGES_IP ec2messages.us-east-1.amazonaws.com" >> /etc/hosts
      systemctl restart amazon-ssm-agent || true
      SSM_CONFIG_STATUS="SUCCESS"
    else
      SSM_CONFIG_STATUS="RESOLUTION_TIMEOUT"
    fi

    # 2. Connectivity verification targeting App A private IP
    APP_A_IP="${aws_instance.app_a.private_ip}"
    mkdir -p /var/log/depi-sec-tests
    TEST_LOG="/var/log/depi-sec-tests/peering-test.log"

    {
      echo "============================================================"
      echo "TASK 18 — VPC PEERING CONNECTIVITY VERIFICATION"
      echo "Timestamp: $(date -u)"
      echo "Source Instance: depi-sec-tools-instance"
      echo "Target App A Private IP: $APP_A_IP"
      echo "SSM Dynamic Discovery: $SSM_CONFIG_STATUS"
      echo "============================================================"

      # 1. ICMP Ping Test
      echo "[TEST 1: ICMP PING]"
      if ping -c 3 -W 3 "$APP_A_IP" > /dev/null 2>&1; then
        echo "Status: SUCCESS (3 packets transmitted, 0% packet loss)"
      else
        echo "Status: FAILED (ICMP ping to $APP_A_IP failed or timed out)"
      fi

      # 2. HTTP Port 80 Curl Test
      echo "[TEST 2: HTTP PORT 80 GET]"
      HTTP_STATUS=$(curl -s -o /dev/null -w "%%{http_code}" --connect-timeout 5 "http://$APP_A_IP")
      if [ "$HTTP_STATUS" = "200" ]; then
        echo "Status: SUCCESS (HTTP 200 OK received from $APP_A_IP)"
        echo "Response snippet:"
        curl -s --connect-timeout 5 "http://$APP_A_IP" | head -n 10
      else
        echo "Status: FAILED (Expected HTTP 200, received: '$HTTP_STATUS')"
      fi
      echo "============================================================"
    } 2>&1 | tee "$TEST_LOG"
  EOF

  tags = {
    Name = "depi-sec-tools-instance"
  }

  lifecycle {
    ignore_changes = [ami]
  }
}
