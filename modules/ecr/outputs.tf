output "repository_url" {
  description = "URL to push and pull images, e.g. <account>.dkr.ecr.<region>.amazonaws.com/<name>"
  value       = aws_ecr_repository.this.repository_url
}
