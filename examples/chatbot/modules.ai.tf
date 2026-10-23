module "ai" {
  source = "./modules/ai"

  location            = var.location
  workload            = var.workload
  resource_group_name = var.resource_group_name
  resource_group_id   = data.azurerm_resource_group.this.id
  tags                = local.tags

  workspace_resource_id = module.observability.workspace_resource_id
  subnet_ids            = local.subnet_ids

  role_assignments_uai = local.role_assignments_uai
  role_assignments     = var.role_assignments
}
