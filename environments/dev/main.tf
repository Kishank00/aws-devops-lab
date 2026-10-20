locals {
  name = "${var.project}-${var.environment}"
}

module "network" {
  source = "../../modules/network"

  name                 = local.name
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

module "ec2" {
  source = "../../modules/ec2"

  name      = local.name
  vpc_id    = module.network.vpc_id
  subnet_id = module.network.private_subnet_ids[0]
}
