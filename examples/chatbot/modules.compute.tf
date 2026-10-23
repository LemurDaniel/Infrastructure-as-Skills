module "compute" {
  source = "./modules/compute"

  location            = var.location
  workload            = var.workload
  resource_group_name = var.resource_group_name
  resource_group_id   = data.azurerm_resource_group.this.id
  tags                = local.tags

  workspace_resource_id = module.observability.workspace_resource_id
  subnet_ids            = local.subnet_ids

  role_assignments_uai = local.role_assignments_uai

  identities                             = module.identity.identities
  host_storage_account_name              = module.data.host_storage_account_name
  application_insights_connection_string = module.observability.insights_connection_string

  # The apps use the roles on the other families' resources while they are being created, and
  # a role takes a while to be effective: the module waits after these exist. A module-level
  # depends_on would defer the module's name lookups to apply, so the ids go in as a value.
  role_scope_ids = [
    module.security.key_vault_resource_id,
    module.ai.foundry_id,
    module.ai.search_id,
    module.data.storage_resource_ids["uploads"],
    module.data.storage_resource_ids["host"],
    module.data.cosmos_resource_id,
    module.observability.insights_resource_id,
  ]
}
