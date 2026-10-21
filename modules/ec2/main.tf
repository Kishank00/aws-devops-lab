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

resource "aws_vpc_security_group_ingress_rule" "http_from_alb" {
  security_group_id            = aws_security_group.ec2.id
  referenced_security_group_id = var.alb_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_instance" "linux_diagnostic_tool" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  user_data_replace_on_change = true

  user_data = file("${path.module}/user_data.sh")
  tags = {
    Name = "${var.name}-diagnostic"
  }
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
