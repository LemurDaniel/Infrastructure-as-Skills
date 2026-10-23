# compute: plan-only, platform mocked, naming provider real. Mocks and variables repeat in every
# file of tests/ - terraform test has no include. The intro comment is in naming.tftest.hcl.

mock_provider "azurerm" {
  mock_data "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we"
    }
  }
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "99999999-8888-7777-6666-555555555555"
    }
  }
}

mock_provider "azapi" {
  # The Flex plan module asks which regions advertise zone-redundant Flex Consumption.
  mock_data "azapi_resource_action" {
    defaults = {
      output = {
        value = [{ properties = { name = "West Europe", orgDomain = "FCZONEREDUNDANCY" } }]
      }
    }
  }
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id          = "11111111-2222-3333-4444-555555555555"
      subscription_resource_id = "/subscriptions/11111111-2222-3333-4444-555555555555"
      tenant_id                = "99999999-8888-7777-6666-555555555555"
    }
  }
}

mock_provider "modtm" {}

variables {
  environment         = "production"
  location            = "westeurope"
  workload            = "chatbot"
  subscription_id     = "11111111-2222-3333-4444-555555555555"
  resource_group_name = "rg-chatbot-prod-we"
  address_space       = "10.20.0.0/16"
  subnets = {
    "snet-endpoints" = { prefix = "10.20.0.0/27" }
    "snet-web"       = { prefix = "10.20.0.64/26" }
    "snet-mcp"       = { prefix = "10.20.0.128/26" }
    "snet-func"      = { prefix = "10.20.0.192/26" }
    "snet-aca"       = { prefix = "10.20.1.0/27" }
  }
}

run "compute" {
  command = plan

  # not-testable: application-insights.component.workspace - the module exposes no attribute for it; set through the module input, reviewed in the call

  # decision: application-insights.component.application_type
  assert {
    condition     = module.observability.insights.resource.application_type == "web"
    error_message = "application-insights.component.application_type must be \"web\", got ${try(jsonencode(module.observability.insights.resource.application_type), "unknown")}."
  }

  # decision: application-insights.component.sampling_percentage
  assert {
    condition     = module.observability.insights.resource.sampling_percentage == 100
    error_message = "application-insights.component.sampling_percentage must be 100, got ${try(jsonencode(module.observability.insights.resource.sampling_percentage), "unknown")}."
  }

  # decision: application-insights.component.daily_cap_gb
  assert {
    condition     = module.observability.insights.resource.daily_data_cap_in_gb == 0
    error_message = "application-insights.component.daily_cap_gb must be 0, got ${try(jsonencode(module.observability.insights.resource.daily_data_cap_in_gb), "unknown")}."
  }

  # decision: application-insights.component.store_client_ip
  assert {
    condition     = module.observability.insights.resource.disable_ip_masking == false
    error_message = "application-insights.component.store_client_ip must be false, got ${try(jsonencode(module.observability.insights.resource.disable_ip_masking), "unknown")}."
  }

  # not-testable: cosmos-db.account.capacity_mode - a container- or region-level setting inside the module's nested inputs, not exposed as an output

  # not-testable: cosmos-db.account.throughput_mode - a container- or region-level setting inside the module's nested inputs, not exposed as an output

  # not-testable: cosmos-db.account.max_throughput - a container- or region-level setting inside the module's nested inputs, not exposed as an output

  # decision: cosmos-db.account.total_throughput_limit
  assert {
    condition     = module.data.cosmos.capacity.total_throughput_limit == -1
    error_message = "cosmos-db.account.total_throughput_limit must be -1, got ${try(jsonencode(module.data.cosmos.capacity.total_throughput_limit), "unknown")}."
  }

  # decision: cosmos-db.account.free_tier
  assert {
    condition     = module.data.cosmos.free_tier_enabled == false
    error_message = "cosmos-db.account.free_tier must be false, got ${try(jsonencode(module.data.cosmos.free_tier_enabled), "unknown")}."
  }

  # not-testable: foundry.account.kind - the module resource output carries no kind or project-management attribute for the AIServices form

  # decision: foundry.account.sku_name
  assert {
    condition     = module.ai.foundry.resource.sku_name == "S0"
    error_message = "foundry.account.sku_name must be \"S0\", got ${try(jsonencode(module.ai.foundry.resource.sku_name), "unknown")}."
  }

  # not-testable: foundry.account.project_management - the module resource output carries no kind or project-management attribute for the AIServices form

  # not-testable: foundry.account.projects - the project is a separate azapi_resource beside the module; its name is its address

  # not-testable: cosmos-db.resilience.zone_redundant - a container- or region-level setting inside the module's nested inputs, not exposed as an output

  # not-testable: cosmos-db.resilience.geo_replicas - a container- or region-level setting inside the module's nested inputs, not exposed as an output

  # decision: cosmos-db.resilience.automatic_failover
  assert {
    condition     = module.data.cosmos.automatic_failover_enabled == true
    error_message = "cosmos-db.resilience.automatic_failover must be true, got ${try(jsonencode(module.data.cosmos.automatic_failover_enabled), "unknown")}."
  }

  # decision: cosmos-db.resilience.consistency_level
  assert {
    condition     = module.data.cosmos.consistency_policy.consistency_level == "Session"
    error_message = "cosmos-db.resilience.consistency_level must be \"Session\", got ${try(jsonencode(module.data.cosmos.consistency_policy.consistency_level), "unknown")}."
  }

  # decision: search-service.service.sku
  assert {
    condition     = module.ai.search.resource.sku == "standard"
    error_message = "search-service.service.sku must be \"standard\", got ${try(jsonencode(module.ai.search.resource.sku), "unknown")}."
  }

  # decision: search-service.service.replica_count
  assert {
    condition     = module.ai.search.resource.replica_count == 2
    error_message = "search-service.service.replica_count must be 2, got ${try(jsonencode(module.ai.search.resource.replica_count), "unknown")}."
  }

  # decision: search-service.service.partition_count
  assert {
    condition     = module.ai.search.resource.partition_count == 1
    error_message = "search-service.service.partition_count must be 1, got ${try(jsonencode(module.ai.search.resource.partition_count), "unknown")}."
  }

  # decision: search-service.service.semantic_ranker
  assert {
    condition     = module.ai.search.resource.semantic_search_sku == "free"
    error_message = "search-service.service.semantic_ranker must be \"free\", got ${try(jsonencode(module.ai.search.resource.semantic_search_sku), "unknown")}."
  }

  # not-testable: container-registry.registry.sku - the container-registry module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-registry.registry.zone_redundant - the container-registry module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-registry.registry.geo_replicas - the container-registry module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-registry.registry.retention_untagged_days - the container-registry module exposes no attribute for it; set through the module input, reviewed in the call

  # decision: container-apps.environment.workload_profile
  assert {
    condition     = module.compute.container_environment.body.properties.workloadProfiles[0].workloadProfileType == "Consumption"
    error_message = "container-apps.environment.workload_profile must be \"Consumption\", got ${try(jsonencode(module.compute.container_environment.body.properties.workloadProfiles[0].workloadProfileType), "unknown")}."
  }

  # decision: container-apps.environment.zone_redundant
  assert {
    condition     = module.compute.container_environment.body.properties.zoneRedundant == true
    error_message = "container-apps.environment.zone_redundant must be true, got ${try(jsonencode(module.compute.container_environment.body.properties.zoneRedundant), "unknown")}."
  }

  # decision: container-apps.environment.internal
  assert {
    condition     = module.compute.container_environment.body.properties.vnetConfiguration.internal == true
    error_message = "container-apps.environment.internal must be true, got ${try(jsonencode(module.compute.container_environment.body.properties.vnetConfiguration.internal), "unknown")}."
  }

  # not-testable: container-apps.environment.infrastructure_subnet - the subnet id is unknown at plan time

  # decision: container-apps.environment.public_network_access
  assert {
    condition     = module.compute.container_environment.body.properties.publicNetworkAccess == "Disabled"
    error_message = "container-apps.environment.public_network_access must be \"Disabled\", got ${try(jsonencode(module.compute.container_environment.body.properties.publicNetworkAccess), "unknown")}."
  }

  # decision: container-apps.environment.peer_traffic_encryption
  assert {
    condition     = module.compute.container_environment.body.properties.peerTrafficConfiguration.encryption.enabled == true
    error_message = "container-apps.environment.peer_traffic_encryption must be true, got ${try(jsonencode(module.compute.container_environment.body.properties.peerTrafficConfiguration.encryption.enabled), "unknown")}."
  }

  # not-testable: container-apps.app.container_image - the container app module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-apps.app.container_size - the container app module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-apps.app.min_replicas - the container app module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-apps.app.max_replicas - the container app module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-apps.app.revision_mode - the container app module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: function-app.hosting.plan_type - set through the plan module's input; the plan module exposes only name and resource_id

  # not-testable: function-app.hosting.runtime_stack - set through the plan module's input; the plan module exposes only name and resource_id

  # not-testable: function-app.hosting.runtime_version - set through the plan module's input; the plan module exposes only name and resource_id

  # not-testable: function-app.hosting.zone_redundant - set through the plan module's input; the plan module exposes only name and resource_id

  # not-testable: function-app.hosting.max_instance_count - set through the plan module's input; the plan module exposes only name and resource_id

  # not-testable: function-app.hosting.always_ready_instances - set through the plan module's input; the plan module exposes only name and resource_id

  # not-testable: function-app.hosting.instance_memory_mb - set through the plan module's input; the plan module exposes only name and resource_id

  # not-testable: app-service__web.hosting.os_type - set through the plan module's input; the plan module exposes only name and resource_id

  # not-testable: app-service__web.hosting.sku - set through the plan module's input; the plan module exposes only name and resource_id

  # not-testable: app-service__web.hosting.zone_redundant - set through the plan module's input; the plan module exposes only name and resource_id

  # not-testable: app-service__web.hosting.instance_count - set through the plan module's input; the plan module exposes only name and resource_id

  # not-testable: app-service__mcp.hosting.os_type - set through the plan module's input; the plan module exposes only name and resource_id

  # not-testable: app-service__mcp.hosting.sku - set through the plan module's input; the plan module exposes only name and resource_id

  # not-testable: app-service__mcp.hosting.zone_redundant - set through the plan module's input; the plan module exposes only name and resource_id

  # not-testable: app-service__mcp.hosting.instance_count - set through the plan module's input; the plan module exposes only name and resource_id

  # not-testable: app-service__web.runtime.runtime_stack - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: app-service__web.runtime.runtime_version - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: app-service__web.runtime.always_on - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: app-service__web.runtime.health_check_path - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: app-service__web.runtime.http2_enabled - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: app-service__mcp.runtime.runtime_stack - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: app-service__mcp.runtime.runtime_version - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: app-service__mcp.runtime.always_on - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: app-service__mcp.runtime.health_check_path - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: app-service__mcp.runtime.http2_enabled - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

}
