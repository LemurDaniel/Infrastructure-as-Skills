data "naming_name" "search" {
  resource   = "Azure::Microsoft.Search/searchServices"
  parameters = { name = "${var.workload}search" }
}

module "search" {
  source  = "Azure/avm-res-search-searchservice/azurerm"
  version = "~> 0.3.0"

  name                = data.naming_name.search.name
  location            = var.location
  resource_group_name = var.resource_group_name

  # decision: search-service.service.sku
  sku = "standard"
  # decision: search-service.service.replica_count - derived from outage_impact; the module
  # default is 1 (Bicep's is 3)
  replica_count = 2
  # decision: search-service.service.partition_count
  partition_count = 1
  # decision: search-service.service.semantic_ranker
  semantic_search_sku = "free"

  # decision: search-service.networking.public_network_access - a bool, module default true
  public_network_access_enabled = false
  # decision: search-service.networking.network_rule_bypass
  network_rule_bypass_option = "None"
  private_endpoints = {
    search = {
      name               = data.naming_name.private_endpoint["search"].name
      subnet_resource_id = var.subnet_ids["snet-endpoints"]
    }
  }
  # deployment.private_dns_records: policy - the platform policy writes the record
  private_endpoints_manage_dns_zone_group = false

  # decision: search-service.identity.managed_identity
  managed_identities = { system_assigned = true }

  # decision: search-service.security.local_authentication_disabled - an inverse input; the
  # module leaves keys on
  local_authentication_enabled = false

  role_assignments = lookup(var.role_assignments_uai, "search-service", {})

  diagnostic_settings = {
    workspace = {
      workspace_resource_id = var.workspace_resource_id
      logs                  = [{ category = "OperationLogs" }]
      metrics               = [{ category = "AllMetrics" }]
    }
  }

  enable_telemetry = true
  tags             = var.tags
}
