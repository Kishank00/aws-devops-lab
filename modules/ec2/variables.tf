variable "vpc_id" {
  description = "ID of the VPC to create the EC2 resources in"
  type        = string
}

variable "subnet_id" {
  description = "ID of the Subnet to create the EC2 resources in"
  type        = string
}

variable "name" {
  description = "Name prefix for every EC2 resource, e.g. devops-lab-dev"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance size"
  type        = string
  default     = "t3.micro"
}

variable "alb_security_group_id" {
  description = "ID of the ALB security group allowed to reach the instance on port 80"
  type        = string
}
