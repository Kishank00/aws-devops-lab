locals {
  app_ports = {
    vm     = 80
    docker = 8080
  }
}

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "ALB: HTTP from internet"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-alb-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_internet" {
  for_each = toset(["80", "8080"])

  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = each.key
  to_port           = each.key
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_lb_target_group" "app" {
  for_each = local.app_ports

  name                 = "${var.name}-${each.key}-tg"
  port                 = each.value
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path    = "/health"
    matcher = "200"
  }
}

resource "aws_lb" "app" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  tags = {
    Name = "${var.name}-alb"
  }
}

resource "aws_lb_listener" "http" {
  for_each = local.app_ports

  load_balancer_arn = aws_lb.app.arn
  port              = each.value
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[each.key].arn
  }
}
