output "state_bucket_name" {
  description = "S3 bucket that holds Terraform state for every stack"
  value       = aws_s3_bucket.tfstate.bucket
}
