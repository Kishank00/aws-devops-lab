variable "name" {
  description = "Name prefix for every ALB resource, e.g. devops-lab-dev"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC to create the ALB resources in"
  type        = string
}

variable "public_subnet_ids" {
  description = "IDs of the public subnets to place the ALB in (at least 2 AZs)"
  type        = list(string)
}
