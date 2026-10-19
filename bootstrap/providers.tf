# Same guard rails as the environments: personal profile only, and any other
# account makes plan/apply fail.
provider "aws" {
  profile             = "personal"
  region              = "ap-south-1"
  allowed_account_ids = ["286590629524"]

  default_tags {
    tags = {
      Project   = "devops-lab"
      Component = "terraform-state"
      ManagedBy = "terraform"
      Owner     = "personal"
    }
  }
}
