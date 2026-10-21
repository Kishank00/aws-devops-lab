module "ecr" {
  source   = "../../modules/ecr"
  for_each = toset(["linux-diagnostic-tool"])
  name     = each.key
}
