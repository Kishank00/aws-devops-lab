# Personal AWS account only. The profile is pinned so this never falls back to
# the WeWork [default] profile, and allowed_account_ids makes plan/apply fail
# if the credentials resolve to any other account.
provider "aws" {
  profile             = "personal"
  region              = "ap-south-1"
  allowed_account_ids = ["286590629524"]

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "personal"
    }
  }
}
