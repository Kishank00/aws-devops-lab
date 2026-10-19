# The bootstrap stack keeps its own state in the bucket it created. On a fresh
# account, comment this block out, apply with local state, then uncomment and
# run `terraform init -migrate-state`.
terraform {
  backend "s3" {
    bucket       = "devops-lab-tfstate-286590629524"
    key          = "bootstrap/terraform.tfstate"
    region       = "ap-south-1"
    profile      = "personal"
    encrypt      = true
    use_lockfile = true
  }
}
