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

variable "image_strategy" {
  description = "fry: stock Ubuntu configured at boot by user_data; bake: the Packer-built AMI with a short boot script"
  type        = string
  default     = "bake"

  validation {
    condition     = contains(["fry", "bake"], var.image_strategy)
    error_message = "image_strategy must be \"fry\" or \"bake\"."
  }
}

