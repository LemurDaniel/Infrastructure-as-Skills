module "security" {
  source = "./modules/security"

  location            = var.location
  workload            = var.workload
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.this.tenant_id
  tags                = local.tags

  workspace_resource_id = module.observability.workspace.resource_id
  subnet_ids            = local.subnet_ids

  role_assignments_uai = local.role_assignments_uai
  secret_placeholders  = var.secret_placeholders
}
