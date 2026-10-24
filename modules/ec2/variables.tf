variable "vpc_id" {
  description = "ID of the VPC to create the EC2 resources in"
  type        = string
}

variable "subnet_ids" {
  description = "IDs of the private subnets the ASG launches instances in, one per AZ"
  type        = list(string)
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
  description = "ID of the ALB security group allowed to reach the instances on ports 80 and 8080"
  type        = string
}

variable "target_group_arns" {
  description = "ARNs of the ALB target groups the ASG registers its instances in"
  type        = list(string)
}
