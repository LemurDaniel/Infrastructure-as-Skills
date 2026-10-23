# Two storage accounts and the conversation store. The accounts are one module call over two
# configurations: they differ only in name, sub-resources and who holds a role.

locals {
  storages = {
    # The users' uploads, read by the web app and indexed by the search service.
    uploads = {
      resource_key = "storage-account__uploads"
      subresources = ["blob"]
    }
    # The state of the connector function (storage-account__host): the Functions host uses
    # blob, queue and table, so it needs an endpoint for each.
    host = {
      resource_key = "storage-account__host"
      subresources = ["blob", "queue", "table"]
    }
  }
}

data "naming_name" "storage_account" {
  for_each = local.storages

  resource   = "Azure::Microsoft.Storage/storageAccounts"
  parameters = { name = "${var.workload}${each.key}" }
}

module "storage" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "~> 0.10.0"

  for_each = local.storages

  name      = data.naming_name.storage_account[each.key].name
  location  = var.location
  parent_id = var.resource_group_id

  account_kind = "StorageV2"
  # decision: storage-account.data_protection.replication - ZRS, derived from outage_impact;
  # the SKU name carries it, and account_tier / account_replication_type are ignored while set
  account_sku_name = "Standard_ZRS"
  # decision: storage-account.data_protection.access_tier
  access_tier = "Hot"

  # decision: storage-account.networking.public_network_access - a bool on the module
  public_network_access_enabled = false
  # decision: storage-account.networking.allow_azure_services_bypass
  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  # Access is via Entra ID and RBAC; the module itself never uses a key.
  shared_access_key_enabled = false
  sftp_enabled              = false
  # Settable only at creation. The module default is false.
  infrastructure_encryption_enabled = true

  managed_identities = {
    system_assigned = true
  }

  blob_properties = {
    versioning_enabled = true
    change_feed        = { enabled = false }
    delete_retention_policy = {
      enabled = true
      days    = 7
    }
    container_delete_retention_policy = {
      enabled = true
      days    = 7
    }
  }

  private_endpoints = {
    for sub in each.value.subresources : sub => {
      name               = data.naming_name.private_endpoint["${each.key}-${sub}"].name
      subnet_resource_id = var.subnet_ids["snet-endpoints"]
      subresource_name   = sub
    }
  }
  # deployment.private_dns_records: policy - the platform policy writes the record
  private_endpoints_manage_dns_zone_group = false

  diagnostic_settings_storage_account = {
    platform = {
      name                  = "diag"
      workspace_resource_id = var.workspace_resource_id
      metrics               = [{ category = "AllMetrics" }]
    }
  }
  diagnostic_settings_blob = {
    platform = {
      name                  = "diag"
      workspace_resource_id = var.workspace_resource_id
      logs                  = [{ category_group = "audit" }]
      metrics               = [{ category = "AllMetrics" }]
    }
  }

  role_assignments = merge(
    lookup(var.role_assignments_uai, each.value.resource_key, {}),
    lookup(var.role_assignments_search, each.value.resource_key, {}),
  )

  enable_telemetry = true
  tags             = var.tags
}
