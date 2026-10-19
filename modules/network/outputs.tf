output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.my_vpc.id
}

output "vpc_arn" {
  description = "ARN of the VPC"
  value       = aws_vpc.my_vpc.arn
}

output "vpc_cidr_block" {
  description = "IPv4 CIDR block of the VPC"
  value       = aws_vpc.my_vpc.cidr_block
}

output "public_subnet_01_cidr_block" {
  description = "IPV4 CIDR block for public subnet 01"
  value       = aws_subnet.public_subnet_01.cidr_block
}

output "public_subnet_01_id" {
  description = "ID of public subnet 01"
  value       = aws_subnet.public_subnet_01.id
}

output "private_subnet_01_cidr_block" {
  description = "IPV4 CIDR block for private subnet 01"
  value       = aws_subnet.private_subnet_01.cidr_block
}

output "private_subnet_01_id" {
  description = "ID of private subnet 01"
  value       = aws_subnet.private_subnet_01.id
}

output "public_subnet_02_cidr_block" {
  description = "IPV4 CIDR block for public subnet 02"
  value       = aws_subnet.public_subnet_02.cidr_block
}

output "public_subnet_02_id" {
  description = "ID of public subnet 02"
  value       = aws_subnet.public_subnet_02.id
}

output "private_subnet_02_cidr_block" {
  description = "IPV4 CIDR block for private subnet 02"
  value       = aws_subnet.private_subnet_02.cidr_block
}

output "private_subnet_02_id" {
  description = "ID of private subnet 02"
  value       = aws_subnet.private_subnet_02.id
}
