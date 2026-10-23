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
  parent_id = data.azurerm_resource_group.this.id

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
      subnet_resource_id = module.network.subnets["snet-endpoints"].resource_id
      subresource_name   = sub
    }
  }
  # deployment.private_dns_records: policy - the platform policy writes the record
  private_endpoints_manage_dns_zone_group = false

  diagnostic_settings_storage_account = {
    platform = {
      name                  = "diag"
      workspace_resource_id = module.workspace.resource_id
      metrics               = [{ category = "AllMetrics" }]
    }
  }
  diagnostic_settings_blob = {
    platform = {
      name                  = "diag"
      workspace_resource_id = module.workspace.resource_id
      logs                  = [{ category_group = "audit" }]
      metrics               = [{ category = "AllMetrics" }]
    }
  }

  role_assignments = merge(
    lookup(local.role_assignments_uai, each.value.resource_key, {}),
    lookup(local.role_assignments_search, each.value.resource_key, {}),
  )

  enable_telemetry = true
  tags             = local.tags
}

data "naming_name" "cosmos" {
  resource = "Azure::Microsoft.DocumentDB/databaseAccounts"
}

module "cosmos" {
  source  = "Azure/avm-res-documentdb-databaseaccount/azurerm"
  version = "~> 0.11.0"

  name                = data.naming_name.cosmos.name
  location            = var.location
  resource_group_name = var.resource_group_name

  # decision: cosmos-db.account.free_tier
  free_tier_enabled = false
  # decision: cosmos-db.account.total_throughput_limit
  capacity = { total_throughput_limit = -1 }

  # decision: cosmos-db.resilience.zone_redundant - derived from outage_impact; the module
  # default is true as well
  geo_locations = [
    { location = var.location, failover_priority = 0, zone_redundant = true },
  ]
  # decision: cosmos-db.resilience.automatic_failover
  automatic_failover_enabled = true
  # decision: cosmos-db.resilience.consistency_level - the module default is BoundedStaleness
  consistency_policy = { consistency_level = "Session" }

  # decision: cosmos-db.networking.public_network_access - a bool
  public_network_access_enabled = false
  # decision: cosmos-db.networking.network_acl_bypass
  network_acl_bypass_for_azure_services = false
  private_endpoints = {
    sql = {
      name               = data.naming_name.private_endpoint["cosmos"].name
      subnet_resource_id = module.network.subnets["snet-endpoints"].resource_id
      subresource_name   = "Sql"
    }
  }
  # deployment.private_dns_records: policy - the platform policy writes the record
  private_endpoints_manage_dns_zone_group = false

  # decision: cosmos-db.security.local_authentication_disabled
  local_authentication_disabled = true
  # decision: cosmos-db.security.key_based_metadata_writes - an inverse input
  access_key_metadata_writes_enabled = false

  # decision: cosmos-db.data_protection.backup_policy - derived from data_loss_tolerance; the
  # module default is Continuous30Days
  backup = { type = "Continuous", tier = "Continuous7Days" }
  # decision: cosmos-db.data_protection.analytical_storage
  analytical_storage_enabled = false

  # decision: cosmos-db.containers.databases - the partition key is the application's
  sql_databases = {
    chatbot = {
      name = "chatbot"
      containers = {
        conversations = {
          name                = "conversations"
          partition_key_paths = ["/userId"]
          # decision: cosmos-db.account.throughput_mode / max_throughput
          autoscale_settings = { max_throughput = 1000 }
        }
      }
    }
  }

  # This module's diagnostic interface differs from the other AVM modules': categories are
  # plain sets, and the only metric categories are Requests and SLI (there is no AllMetrics).
  diagnostic_settings = {
    workspace = {
      workspace_resource_id = module.workspace.resource_id
      log_categories        = ["ControlPlaneRequests", "DataPlaneRequests"]
      log_groups            = []
      metric_categories     = ["Requests"]
    }
  }

  role_assignments = lookup(local.role_assignments_uai, "cosmos-db", {})

  enable_telemetry = true
  tags             = local.tags
}

# Cosmos DB's own data-plane roles: the AVM Terraform module has no input for them, and the
# Azure role of the same name does not read an item. Built-in role ids end 0001 (reader) and
# 0002 (contributor).
locals {
  cosmos_data_roles = {
    "Cosmos DB Built-in Data Reader"      = "00000000-0000-0000-0000-000000000001"
    "Cosmos DB Built-in Data Contributor" = "00000000-0000-0000-0000-000000000002"
  }
}

resource "azurerm_cosmosdb_sql_role_assignment" "this" {
  for_each = { for a in var.cosmos_data_role_assignments : "${a.principal}/${a.role}" => a }

  resource_group_name = var.resource_group_name
  account_name        = module.cosmos.name
  role_definition_id  = "${module.cosmos.resource_id}/sqlRoleDefinitions/${local.cosmos_data_roles[each.value.role]}"
  principal_id        = local.uai_principal_ids[each.value.principal]
  scope               = module.cosmos.resource_id
}
