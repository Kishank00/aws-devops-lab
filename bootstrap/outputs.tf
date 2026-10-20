output "state_bucket_name" {
  description = "S3 bucket that holds Terraform state for every stack"
  value       = aws_s3_bucket.tfstate.bucket
}

output "app_deploy_role_arn" {
  description = "Role the app repo's GitHub Actions assumes to deploy via SSM"
  value       = aws_iam_role.app_deploy.arn
}
