resource "aws_lb" "alb" {
  name               = "depi-sec-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  tags = {
    Name = "depi-sec-alb"
  }
}

resource "aws_lb_target_group" "app_tg" {
  name        = "depi-sec-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.app_vpc.id
  target_type = "instance"

  health_check {
    path     = "/"
    protocol = "HTTP"
    interval = 30
  }

  tags = {
    Name = "depi-sec-tg"
  }
}

resource "aws_lb_target_group_attachment" "app_a" {
  target_group_arn = aws_lb_target_group.app_tg.arn
  target_id        = aws_instance.app_a.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "app_b" {
  target_group_arn = aws_lb_target_group.app_tg.arn
  target_id        = aws_instance.app_b.id
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Access Denied"
      status_code  = "403"
    }
  }
}

resource "aws_lb_listener_rule" "allow_cloudfront" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }

  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = [random_password.origin_verify_header.result]
    }
  }
}
