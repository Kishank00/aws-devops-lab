packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1.8.3"
    }
    ansible = {
      version = "~> 1.1.6"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

locals {
  # Unique per build, e.g. 20261024-1730 (UTC)
  build_time = formatdate("YYYYMMDD-hhmm", timestamp())
}

# Where and how to build: a temporary EC2 from stock Ubuntu, snapshotted into an AMI
source "amazon-ebs" "sysdiag" {
  profile       = "personal-sdk"
  region        = "ap-south-1"
  instance_type = "t3.micro"

  # Same base image as data "aws_ami" "ubuntu" in modules/ec2
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
      virtualization-type = "hvm"
    }
    owners      = ["099720109477"] # Canonical
    most_recent = true
  }

  ssh_username = "ubuntu"

  # Packer opens SSH on a temporary security group; allow only this machine's public IP
  temporary_security_group_source_public_ip = true

  ami_name        = "sysdiag-base-${local.build_time}"
  ami_description = "Ubuntu 24.04 with nginx, Docker and the sysdiag app baked in"

  tags = {
    Name      = "sysdiag-base-${local.build_time}"
    BuiltBy   = "packer"
    BaseAMI   = "{{ .SourceAMI }}"
    BuildTime = local.build_time
  }
}

build {
  sources = ["source.amazon-ebs.sysdiag"]

  # 1. Wait until Ubuntu's own first-boot setup (cloud-init) is finished,
  #    otherwise apt is locked and Ansible fails
  provisioner "shell" {
    inline = ["cloud-init status --wait"]
  }

  # 2. Configure the server with the Ansible playbook
  provisioner "ansible" {
    playbook_file = "./ansible/playbook.yml"
    use_proxy     = false
  }
}
