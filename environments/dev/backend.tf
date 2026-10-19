# State lives in the bucket created by bootstrap/. use_lockfile takes an S3
# lock object while a plan/apply runs, so two runs can never write at once.
terraform {
  backend "s3" {
    bucket       = "devops-lab-tfstate-286590629524"
    key          = "dev/network/terraform.tfstate"
    region       = "ap-south-1"
    profile      = "personal"
    encrypt      = true
    use_lockfile = true
  }
}
