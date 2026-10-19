variable "project" {
  description = "Project name, used in resource names and tags"
  type        = string
}

variable "environment" {
  description = "Environment name, e.g. dev or prod"
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for this environment's VPC"
  type        = string
}
variable "public_subnet_cidrs" {
  description = "IPv4 CIDR blocks for the public subnets, one per AZ"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "IPv4 CIDR blocks for the private subnets, one per AZ"
  type        = list(string)
}

variable "availability_zones" {
  description = "AZs to spread subnets across"
  type        = list(string)
}
