module "observability" {
  source = "./modules/observability"

  location            = var.location
  workload            = var.workload
  resource_group_name = var.resource_group_name
  resource_group_id   = data.azurerm_resource_group.this.id
  tags                = local.tags

  role_assignments_uai = local.role_assignments_uai
}
