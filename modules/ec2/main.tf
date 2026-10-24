resource "aws_security_group" "ec2" {
  name        = "${var.name}-ec2-sg"
  description = "EC2 instance: no inbound, all outbound"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-ec2-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.ec2.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  for_each = toset(["80", "8080"])

  security_group_id            = aws_security_group.ec2.id
  referenced_security_group_id = var.alb_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = each.key
  to_port                      = each.key
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_launch_template" "app" {
  name_prefix            = "${var.name}-app-"
  image_id               = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.ec2.id]
  user_data              = base64encode(file("${path.module}/user_data.sh"))
  update_default_version = true

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.name}-diagnostic"
    }
  }
}

resource "aws_autoscaling_group" "app" {
  name                      = "${var.name}-asg"
  vpc_zone_identifier       = var.subnet_ids
  max_size                  = 4
  min_size                  = 2
  health_check_grace_period = 600
  health_check_type         = "ELB"
  desired_capacity          = 2
  target_group_arns         = var.target_group_arns
  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = 200
    }
  }
  depends_on = [aws_iam_role_policy_attachment.this, aws_ssm_parameter.image_tag]
}


data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

  }
}

resource "aws_iam_role" "ec2" {
  name               = "${var.name}-ec2-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = {
    "ssm"      = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "ecr_read" = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  }
  role       = aws_iam_role.ec2.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.name}-ec2-ssm-profile"
  role = aws_iam_role.ec2.name
}

resource "aws_ssm_parameter" "image_tag" {
  name        = "/${var.name}/sysdiag/image-tag"
  description = "Image tag of the live sysdiag container, updated by the app CI after each deploy"
  type        = "String"
  value       = "33413c36d9bc6eb53c6a35259238be2e1930ac7a"

  lifecycle {
    ignore_changes = [value]
  }
}
