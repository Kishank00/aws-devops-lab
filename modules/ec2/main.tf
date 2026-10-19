resource "aws_security_group" "ec2" {
  name        = "devops-lab-dev-ec2-sg"
  description = "EC2 instance: no inbound, all outbound"
  vpc_id      = var.vpc_id

  tags = {
    Name = "devops-lab-dev-ec2-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.ec2.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
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
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.ec2.id]

  tags = {
    Name = "linux_diagnostic_tool"
  }
}
