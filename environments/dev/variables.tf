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

variable "public_subnet_cidr_01" {
  description = "IPV4 CIDR block for public subnet in my_vpc"
  type        = string
}

variable "private_subnet_cidr_01" {
  description = "IPV4 CIDR block for private subnet in my_vpc"
  type        = string
}

variable "availability_zone_1" {
  description = "Availability zones for the High Availability of the applications"
  type        = string
}

variable "public_subnet_cidr_02" {
  description = "IPV4 CIDR block for public subnet 02 in my_vpc"
  type        = string
}

variable "private_subnet_cidr_02" {
  description = "IPV4 CIDR block for private subnet 02 in my_vpc"
  type        = string
}

variable "availability_zone_2" {
  description = "Availability zones for the High Availability of the applications"
  type        = string
}
