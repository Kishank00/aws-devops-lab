variable "name" {
  description = "Name prefix for every network resource, e.g. \"devops-lab-dev\""
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.name))
    error_message = "name must be 3-32 characters of lowercase letters, digits and hyphens."
  }
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC (AWS allows /16 to /28)"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 28
    error_message = "vpc_cidr must be a valid IPv4 CIDR between /16 and /28, e.g. \"10.0.0.0/16\"."
  }
}

variable "tags" {
  description = "Extra tags added to every resource in this module"
  type        = map(string)
  default     = {}
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
