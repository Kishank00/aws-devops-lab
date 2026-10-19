output "vpc_id" {
  description = "ID of the dev VPC"
  value       = module.network.vpc_id
}

output "vpc_cidr_block" {
  description = "IPv4 CIDR block of the dev VPC"
  value       = module.network.vpc_cidr_block
}

output "public_subnet_01_cidr_block" {
  description = "IPV4 CIDR block for public subnet 01"
  value       = module.network.public_subnet_01_cidr_block
}

output "public_subnet_01_id" {
  description = "ID of public subnet 01"
  value       = module.network.public_subnet_01_id
}

output "private_subnet_01_cidr_block" {
  description = "IPV4 CIDR block for private subnet 01"
  value       = module.network.private_subnet_01_cidr_block
}

output "private_subnet_01_id" {
  description = "ID of private subnet 01"
  value       = module.network.private_subnet_01_id
}

output "public_subnet_02_cidr_block" {
  description = "IPV4 CIDR block for public subnet 02"
  value       = module.network.public_subnet_02_cidr_block
}

output "public_subnet_02_id" {
  description = "ID of public subnet 02"
  value       = module.network.public_subnet_02_id
}

output "private_subnet_02_cidr_block" {
  description = "IPV4 CIDR block for private subnet 02"
  value       = module.network.private_subnet_02_cidr_block
}

output "private_subnet_02_id" {
  description = "ID of private subnet 02"
  value       = module.network.private_subnet_02_id
}
