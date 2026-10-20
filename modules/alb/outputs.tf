output "security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "dns_name" {
  description = "Public DNS name of the ALB"
  value       = aws_lb.app.dns_name
}
