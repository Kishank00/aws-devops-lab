output "security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "dns_name" {
  description = "Public DNS name of the ALB"
  value       = aws_lb.app.dns_name
}

output "target_group_arns" {
  description = "ARNs of the app target groups (vm :80, docker :8080)"
  value       = [for key, tg in aws_lb_target_group.app : tg.arn]
}
