# compute: plan-only, run with `terraform -chdir=modules/compute test`. The family module is the
# unit under test, so an assert reads the AVM module by its own name (module.foundry) and the
# rendered names from the data sources beside it. Mocks and variables repeat in every file of
# tests/ - terraform test has no include.

mock_provider "azurerm" {
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

mock_provider "modtm" {
}

# The naming provider stays real, so rendered names are asserted as they will be deployed.
# The seed is the root's: <subscription_id>/<resource_group_name>.
provider "naming" {
  convention  = "default"
  naming      = "../../naming.yaml"
  random_seed = "11111111-2222-3333-4444-555555555555/rg-chatbot-prod-we"

  parameters = {
    location    = "westeurope"
    environment = "production"
    name        = "chatbot"
  }
}

variables {
  location              = "westeurope"
  workload              = "chatbot"
  resource_group_name   = "rg-chatbot-prod-we"
  resource_group_id     = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we"
  tags                  = {}
  workspace_resource_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.OperationalInsights/workspaces/log-we-prod-chatbot-01"
  subnet_ids = {
    "snet-endpoints" = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.Network/virtualNetworks/vnet-we-prod-chatbot-01/subnets/snet-endpoints"
    "snet-web"       = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.Network/virtualNetworks/vnet-we-prod-chatbot-01/subnets/snet-web"
    "snet-mcp"       = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.Network/virtualNetworks/vnet-we-prod-chatbot-01/subnets/snet-mcp"
    "snet-func"      = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.Network/virtualNetworks/vnet-we-prod-chatbot-01/subnets/snet-func"
    "snet-aca"       = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.Network/virtualNetworks/vnet-we-prod-chatbot-01/subnets/snet-aca"
  }
  role_assignments_uai = {}
  identities = {
    web       = { resource_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-we-prod-chatbotweb-01", client_id = "00000000-0000-0000-0000-000000000001" }
    connector = { resource_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-we-prod-chatbotconnector-01", client_id = "00000000-0000-0000-0000-000000000002" }
    runner    = { resource_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-we-prod-chatbotrunner-01", client_id = "00000000-0000-0000-0000-000000000003" }
  }
  host_storage_account_name              = "stweprodchatbothost01"
  application_insights_connection_string = "InstrumentationKey=00000000-0000-0000-0000-000000000000"
  role_scope_ids                         = []
}

# --- compute ---
run "compute" {
  command = plan

  # not-testable: container-registry.registry.sku - the container-registry module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-registry.registry.zone_redundant - the container-registry module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-registry.registry.geo_replicas - the container-registry module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-registry.registry.retention_untagged_days - the container-registry module exposes no attribute for it; set through the module input, reviewed in the call

  # decision: container-apps.environment.workload_profile
  assert {
    condition     = azapi_resource.container_environment.body.properties.workloadProfiles[0].workloadProfileType == "Consumption"
    error_message = "container-apps.environment.workload_profile must be \"Consumption\", got ${try(jsonencode(azapi_resource.container_environment.body.properties.workloadProfiles[0].workloadProfileType), "unknown")}."
  }

  # decision: container-apps.environment.zone_redundant
  assert {
    condition     = azapi_resource.container_environment.body.properties.zoneRedundant == true
    error_message = "container-apps.environment.zone_redundant must be true, got ${try(jsonencode(azapi_resource.container_environment.body.properties.zoneRedundant), "unknown")}."
  }

  # decision: container-apps.environment.internal
  assert {
    condition     = azapi_resource.container_environment.body.properties.vnetConfiguration.internal == true
    error_message = "container-apps.environment.internal must be true, got ${try(jsonencode(azapi_resource.container_environment.body.properties.vnetConfiguration.internal), "unknown")}."
  }

  # not-testable: container-apps.environment.infrastructure_subnet - the subnet id is unknown at plan time

  # decision: container-apps.environment.public_network_access
  assert {
    condition     = azapi_resource.container_environment.body.properties.publicNetworkAccess == "Disabled"
    error_message = "container-apps.environment.public_network_access must be \"Disabled\", got ${try(jsonencode(azapi_resource.container_environment.body.properties.publicNetworkAccess), "unknown")}."
  }

  # decision: container-apps.environment.peer_traffic_encryption
  assert {
    condition     = azapi_resource.container_environment.body.properties.peerTrafficConfiguration.encryption.enabled == true
    error_message = "container-apps.environment.peer_traffic_encryption must be true, got ${try(jsonencode(azapi_resource.container_environment.body.properties.peerTrafficConfiguration.encryption.enabled), "unknown")}."
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

# --- data_protection ---
run "data_protection" {
  command = plan

  # not-testable: function-app.storage.host_storage_account - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: function-app.storage.host_storage_auth - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: function-app.storage.deployment_container - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call
}

# --- identity ---
run "identity" {
  command = plan

  # not-testable: container-registry.identity.managed_identity - the container-registry module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-registry.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read

  # not-testable: container-apps.identity.managed_identity - the container app module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-apps.identity.user_assigned_identity_ids - the identity assignment is a child of the module call; the root cannot read it back

  # not-testable: container-apps.identity.secret_references - the container app module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-apps.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read

  # not-testable: function-app.identity.managed_identity - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: function-app.identity.user_assigned_identity_ids - the identity assignment is a child of the module call; the root cannot read it back

  # not-testable: function-app.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read

  # not-testable: app-service__web.identity.managed_identity - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: app-service__web.identity.user_assigned_identity_ids - the identity assignment is a child of the module call; the root cannot read it back

  # not-testable: app-service__mcp.identity.managed_identity - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: app-service__mcp.identity.user_assigned_identity_ids - the identity assignment is a child of the module call; the root cannot read it back
}

# --- naming ---
run "naming" {
  command = plan

  assert {
    condition     = data.naming_name.registry.name == "crweprodchatbot01"
    error_message = "The registry name must come from naming.yaml: crweprodchatbot01, got ${data.naming_name.registry.name}."
  }

  assert {
    condition     = data.naming_name.app["web"].name == "app-we-prod-chatbotweb-01"
    error_message = "The web app name must come from naming.yaml: app-we-prod-chatbotweb-01, got ${data.naming_name.app["web"].name}."
  }

  assert {
    condition     = data.naming_name.function.name == "func-we-prod-chatbotfunc-01"
    error_message = "The connector function name must come from naming.yaml: func-we-prod-chatbotfunc-01, got ${data.naming_name.function.name}."
  }

  assert {
    condition     = data.naming_name.private_endpoint["web"].name == "pep-we-prod-chatbotweb-sites-01"
    error_message = "The web app private endpoint name must come from naming.yaml: pep-we-prod-chatbotweb-sites-01, got ${data.naming_name.private_endpoint["web"].name}."
  }
}

# --- networking ---
run "networking" {
  command = plan

  # not-testable: container-registry.networking.public_network_access - the container-registry module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-registry.networking.private_endpoint_subnet - the private endpoint is a child resource of the module; the root sees only its name

  # not-testable: container-registry.networking.network_rule_bypass - the container-registry module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-registry.networking.export_policy_enabled - the container-registry module exposes no attribute for it; set through the module input, reviewed in the call

  # decision: function-app.networking.public_network_access
  assert {
    condition     = module.function.resource.body.properties.publicNetworkAccess == "Disabled"
    error_message = "function-app.networking.public_network_access must be \"Disabled\", got ${try(jsonencode(module.function.resource.body.properties.publicNetworkAccess), "unknown")}."
  }

  # not-testable: function-app.networking.private_endpoint_subnet - the private endpoint is a child resource of the module; the root sees only its name

  # not-testable: function-app.networking.vnet_integration - the integration is the subnet id, unknown at plan time

  # not-testable: function-app.networking.integration_subnet - the subnet id is unknown at plan time

  # decision: function-app.networking.vnet_route_all
  assert {
    condition     = module.function.resource.body.properties.outboundVnetRouting.allTraffic == true
    error_message = "function-app.networking.vnet_route_all must be true, got ${try(jsonencode(module.function.resource.body.properties.outboundVnetRouting.allTraffic), "unknown")}."
  }

  # decision: app-service__web.networking.public_network_access
  assert {
    condition     = module.app["web"].resource.body.properties.publicNetworkAccess == "Disabled"
    error_message = "app-service__web.networking.public_network_access must be \"Disabled\", got ${try(jsonencode(module.app["web"].resource.body.properties.publicNetworkAccess), "unknown")}."
  }

  # not-testable: app-service__web.networking.private_endpoint_subnet - the private endpoint is a child resource of the module; the root sees only its name

  # not-testable: app-service__web.networking.vnet_integration - the integration is the subnet id, unknown at plan time

  # not-testable: app-service__web.networking.integration_subnet - the subnet id is unknown at plan time

  # decision: app-service__web.networking.vnet_route_all
  assert {
    condition     = module.app["web"].resource.body.properties.outboundVnetRouting.allTraffic == true
    error_message = "app-service__web.networking.vnet_route_all must be true, got ${try(jsonencode(module.app["web"].resource.body.properties.outboundVnetRouting.allTraffic), "unknown")}."
  }

  # decision: app-service__mcp.networking.public_network_access
  assert {
    condition     = module.app["mcp"].resource.body.properties.publicNetworkAccess == "Disabled"
    error_message = "app-service__mcp.networking.public_network_access must be \"Disabled\", got ${try(jsonencode(module.app["mcp"].resource.body.properties.publicNetworkAccess), "unknown")}."
  }

  # not-testable: app-service__mcp.networking.private_endpoint_subnet - the private endpoint is a child resource of the module; the root sees only its name

  # not-testable: app-service__mcp.networking.vnet_integration - the integration is the subnet id, unknown at plan time

  # not-testable: app-service__mcp.networking.integration_subnet - the subnet id is unknown at plan time

  # decision: app-service__mcp.networking.vnet_route_all
  assert {
    condition     = module.app["mcp"].resource.body.properties.outboundVnetRouting.allTraffic == true
    error_message = "app-service__mcp.networking.vnet_route_all must be true, got ${try(jsonencode(module.app["mcp"].resource.body.properties.outboundVnetRouting.allTraffic), "unknown")}."
  }

  # not-testable: container-apps.ingress.ingress - the container app module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-apps.ingress.target_port - the container app module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-apps.ingress.allow_insecure - the container app module exposes no attribute for it; set through the module input, reviewed in the call
}

# --- observability ---
run "observability" {
  command = plan

  # not-testable: container-registry.observability.diagnostic_workspace - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: container-registry.observability.diagnostic_categories - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: container-registry.observability.metrics_enabled - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: container-apps.observability.diagnostic_workspace - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: container-apps.observability.diagnostic_categories - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: container-apps.observability.metrics_enabled - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: function-app.observability.diagnostic_workspace - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: function-app.observability.diagnostic_categories - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: function-app.observability.metrics_enabled - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: app-service__web.observability.diagnostic_workspace - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: app-service__web.observability.diagnostic_categories - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: app-service__web.observability.metrics_enabled - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: app-service__mcp.observability.diagnostic_workspace - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: app-service__mcp.observability.diagnostic_categories - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: app-service__mcp.observability.metrics_enabled - the diagnostic setting is built by the module in a child resource, which the root cannot read
}

# --- security ---
run "security" {
  command = plan

  # not-testable: container-registry.security.admin_enabled - the container-registry module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-registry.security.anonymous_pull_enabled - the container-registry module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-registry.security.key_management - platform-managed keys: the module is given no key, nothing to observe

  # decision: function-app.security.https_only
  assert {
    condition     = module.function.resource.body.properties.httpsOnly == true
    error_message = "function-app.security.https_only must be true, got ${try(jsonencode(module.function.resource.body.properties.httpsOnly), "unknown")}."
  }

  # decision: function-app.security.min_tls_version
  assert {
    condition     = module.function.resource.body.properties.siteConfig.minTlsVersion == "1.2"
    error_message = "function-app.security.min_tls_version must be \"1.2\", got ${try(jsonencode(module.function.resource.body.properties.siteConfig.minTlsVersion), "unknown")}."
  }

  # not-testable: function-app.security.basic_auth_enabled - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: function-app.security.application_insights - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # decision: app-service__web.security.https_only
  assert {
    condition     = module.app["web"].resource.body.properties.httpsOnly == true
    error_message = "app-service__web.security.https_only must be true, got ${try(jsonencode(module.app["web"].resource.body.properties.httpsOnly), "unknown")}."
  }

  # decision: app-service__web.security.min_tls_version
  assert {
    condition     = module.app["web"].resource.body.properties.siteConfig.minTlsVersion == "1.2"
    error_message = "app-service__web.security.min_tls_version must be \"1.2\", got ${try(jsonencode(module.app["web"].resource.body.properties.siteConfig.minTlsVersion), "unknown")}."
  }

  # not-testable: app-service__web.security.ftps_state - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: app-service__web.security.basic_auth_enabled - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # decision: app-service__mcp.security.https_only
  assert {
    condition     = module.app["mcp"].resource.body.properties.httpsOnly == true
    error_message = "app-service__mcp.security.https_only must be true, got ${try(jsonencode(module.app["mcp"].resource.body.properties.httpsOnly), "unknown")}."
  }

  # decision: app-service__mcp.security.min_tls_version
  assert {
    condition     = module.app["mcp"].resource.body.properties.siteConfig.minTlsVersion == "1.2"
    error_message = "app-service__mcp.security.min_tls_version must be \"1.2\", got ${try(jsonencode(module.app["mcp"].resource.body.properties.siteConfig.minTlsVersion), "unknown")}."
  }

  # not-testable: app-service__mcp.security.ftps_state - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: app-service__mcp.security.basic_auth_enabled - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call
}
