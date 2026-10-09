data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_instance" "app_a" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private_a.id
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = false
  depends_on                  = [aws_efs_mount_target.efs_mt_a, aws_efs_mount_target.efs_mt_b]

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
  }

  user_data = <<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y nginx amazon-efs-utils
    systemctl enable nginx
    systemctl start nginx

    mkdir -p /mnt/shared
    echo "${aws_efs_file_system.efs.id} /mnt/shared efs _netdev,noresvport,tls,accesspoint=${aws_efs_access_point.efs_ap.id} 0 0" >> /etc/fstab
    mount -a -t efs

    TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    AZ=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
    
    cat <<HTML > /usr/share/nginx/html/index.html
    <!DOCTYPE html>
    <html>
    <head><title>depi-sec-app-a</title></head>
    <body>
      <h1>depi-sec-app-a</h1>
      <p>AZ: $AZ</p>
    </body>
    </html>
    HTML
  EOF

  tags = {
    Name = "depi-sec-app-a"
  }
}

resource "aws_instance" "app_b" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private_b.id
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = false
  depends_on                  = [aws_efs_mount_target.efs_mt_a, aws_efs_mount_target.efs_mt_b]

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
  }

  user_data = <<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y nginx amazon-efs-utils
    systemctl enable nginx
    systemctl start nginx

    mkdir -p /mnt/shared
    echo "${aws_efs_file_system.efs.id} /mnt/shared efs _netdev,noresvport,tls,accesspoint=${aws_efs_access_point.efs_ap.id} 0 0" >> /etc/fstab
    mount -a -t efs

    TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    AZ=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
    
    cat <<HTML > /usr/share/nginx/html/index.html
    <!DOCTYPE html>
    <html>
    <head><title>depi-sec-app-b</title></head>
    <body>
      <h1>depi-sec-app-b</h1>
      <p>AZ: $AZ</p>
    </body>
    </html>
    HTML
  EOF

  tags = {
    Name = "depi-sec-app-b"
  }
}
