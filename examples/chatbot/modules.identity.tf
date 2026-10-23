# Created first: the apps pull their image and read their storage while they are being created,
# so the identity has to hold its roles before they exist.
module "identity" {
  source = "./modules/identity"

  location            = var.location
  workload            = var.workload
  resource_group_name = var.resource_group_name
  tags                = local.tags
}
