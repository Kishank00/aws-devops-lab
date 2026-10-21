output "ecr_repository_urls" {
  description = "ECR repository URL for each app"
  value       = { for name, repo in module.ecr : name => repo.repository_url }
}
