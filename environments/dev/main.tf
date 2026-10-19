locals {
  name = "${var.project}-${var.environment}"
}

module "network" {
  source = "../../modules/network"

  name                   = local.name
  vpc_cidr               = var.vpc_cidr
  public_subnet_cidr_01  = var.public_subnet_cidr_01
  public_subnet_cidr_02  = var.public_subnet_cidr_02
  private_subnet_cidr_01 = var.private_subnet_cidr_01
  private_subnet_cidr_02 = var.private_subnet_cidr_02
  availability_zone_1    = var.availability_zone_1
  availability_zone_2    = var.availability_zone_2
}
