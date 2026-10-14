resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name        = "depi-sec-db-subnet-group"
  description = "Database subnet group for private subnets"
  subnet_ids  = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = {
    Name = "depi-sec-db-subnet-group"
  }
}

resource "aws_db_instance" "db" {
  identifier             = "depi-sec-db"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  storage_type           = "gp3"
  multi_az               = false
  publicly_accessible    = false
  storage_encrypted      = true
  skip_final_snapshot    = true
  deletion_protection    = false
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  db_name                = "depisecdb"
  username               = "admin"
  password               = random_password.db_password.result
  apply_immediately      = true

  tags = {
    Name = "depi-sec-db"
  }
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "depi-sec-db-credentials"
  description             = "Master credentials for RDS MySQL database"
  recovery_window_in_days = 0

  tags = {
    Name = "depi-sec-db-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    engine   = "mysql"
    host     = aws_db_instance.db.address
    port     = aws_db_instance.db.port
    username = aws_db_instance.db.username
    password = random_password.db_password.result
    database = aws_db_instance.db.db_name
  })
}
