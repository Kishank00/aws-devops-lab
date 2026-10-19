provider "aws" {
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
