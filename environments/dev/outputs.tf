output "vpc_id" {
  description = "ID of the dev VPC"
  value       = module.network.vpc_id
}

output "vpc_cidr_block" {
  description = "IPv4 CIDR block of the dev VPC"
  value       = module.network.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.network.private_subnet_ids
}

output "asg_name" {
  description = "Name of the app Auto Scaling Group"
  value       = module.ec2.asg_name
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.dns_name
}
