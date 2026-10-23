module "network" {
  source = "./modules/network"

  location            = var.location
  workload            = var.workload
  resource_group_name = var.resource_group_name
  resource_group_id   = data.azurerm_resource_group.this.id
  tags                = local.tags

  workspace_resource_id = module.observability.workspace.resource_id

  address_space = var.address_space
  subnets       = var.subnets
}
