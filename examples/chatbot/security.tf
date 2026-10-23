data "naming_name" "key_vault" {
  resource = "Azure::Microsoft.KeyVault/vaults"
}

# The AVM Terraform module is `Orphaned` in the AVM index: it works and has no owner, so a
# fix may be slow (handover).
module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "~> 0.12.0"

  name                = data.naming_name.key_vault.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.this.tenant_id

  # decision: key-vault.vault.sku - the module default is premium
  sku_name = "standard"
  # decision: key-vault.vault.purge_protection
  purge_protection_enabled = true
  # decision: key-vault.vault.soft_delete_retention_days
  soft_delete_retention_days = 90
  # decision: key-vault.vault.rbac_authorization - an inverse input
  legacy_access_policies_enabled = false

  # decision: key-vault.networking.public_network_access - a bool, module default true
  public_network_access_enabled = false
  # decision: key-vault.networking.network_acl_bypass
  network_acls = {
    bypass         = "None"
    default_action = "Deny"
    ip_rules       = []
  }
  private_endpoints = {
    vault = {
      name               = data.naming_name.private_endpoint["kv"].name
      subnet_resource_id = module.network.subnets["snet-endpoints"].resource_id
    }
  }
  # deployment.private_dns_records: policy - the platform policy writes the record
  private_endpoints_manage_dns_zone_group = false

  # decision: key-vault.security.enabled_for_services - all three written
  enabled_for_deployment          = false
  enabled_for_disk_encryption     = false
  enabled_for_template_deployment = false

  role_assignments = lookup(local.role_assignments_uai, "key-vault", {})

  diagnostic_settings = {
    workspace = {
      workspace_resource_id = module.workspace.resource_id
      logs = [
        { category = "AuditEvent" },
        { category = "AzurePolicyEvaluationDetails" },
      ]
      metrics = [{ category = "AllMetrics" }]
    }
  }

  enable_telemetry = true
  tags             = local.tags
}

# decision: key-vault.security.secret_placeholders - empty slots a consumer's reference can
# resolve, filled in afterwards by hand or by the workload. Outside the module, so the value
# can be ignored: neither module protects a filled-in value from the next apply.
resource "azurerm_key_vault_secret" "placeholder" {
  for_each = toset(var.secret_placeholders)

  name         = each.key
  key_vault_id = module.key_vault.resource_id
  value        = "placeholder - replace after deployment"
  content_type = "placeholder"

  lifecycle {
    ignore_changes = [value, tags]
  }
}
