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
      subnet_resource_id = var.subnet_ids["snet-endpoints"]
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
      workspace_resource_id = var.workspace_resource_id
      log_categories        = ["ControlPlaneRequests", "DataPlaneRequests"]
      log_groups            = []
      metric_categories     = ["Requests"]
    }
  }

  role_assignments = lookup(var.role_assignments_uai, "cosmos-db", {})

  enable_telemetry = true
  tags             = var.tags
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
  principal_id        = var.uai_principal_ids[each.value.principal]
  scope               = module.cosmos.resource_id
}
