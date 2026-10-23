# networking: plan-only, platform mocked, naming provider real. Mocks and variables repeat in every
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

run "networking" {
  command = plan

  # decision: virtual-network.addressing.address_space
  assert {
    condition     = jsonencode(module.network.network.resource.body.properties.addressSpace.addressPrefixes) == jsonencode(["10.20.0.0/16"])
    error_message = "virtual-network.addressing.address_space must be [\"10.20.0.0/16\"], got ${try(jsonencode(module.network.network.resource.body.properties.addressSpace.addressPrefixes), "unknown")}."
  }

  # decision: virtual-network.addressing.subnets
  assert {
    condition     = jsonencode(sort(keys(module.network.network.subnets))) == jsonencode(["snet-aca", "snet-endpoints", "snet-func", "snet-mcp", "snet-web"])
    error_message = "virtual-network.addressing.subnets must be [\"snet-aca\", \"snet-endpoints\", \"snet-func\", \"snet-mcp\", \"snet-web\"], got ${try(jsonencode(sort(keys(module.network.network.subnets))), "unknown")}."
  }

  # not-testable: virtual-network.addressing.private_endpoint_subnet_prefix - the subnet is a child resource of the module, which the root cannot read

  # decision: virtual-network.addressing.dns_servers
  assert {
    condition     = module.network.network.resource.body.properties.dhcpOptions == null
    error_message = "virtual-network.addressing.dns_servers must be null, got ${try(jsonencode(module.network.network.resource.body.properties.dhcpOptions), "unknown")}."
  }

  # not-testable: virtual-network.subnet_policy.private_endpoint_network_policies - the subnet is a child resource of the module, which the root cannot read

  # not-testable: virtual-network.subnet_policy.service_endpoints - the subnet is a child resource of the module, which the root cannot read

  # not-testable: virtual-network.subnet_policy.subnet_delegations - the subnet is a child resource of the module, which the root cannot read

  # not-testable: network-security-group__endpoints.rules.subnet_purpose - the module exposes only name, resource_id and the rules as unknown-at-plan ids; the rule set is reviewed in the call

  # not-testable: network-security-group__endpoints.rules.default_inbound - the module exposes only name, resource_id and the rules as unknown-at-plan ids; the rule set is reviewed in the call

  # not-testable: network-security-group__endpoints.rules.default_outbound - the module exposes only name, resource_id and the rules as unknown-at-plan ids; the rule set is reviewed in the call

  # not-testable: network-security-group__endpoints.rules.rules - the module exposes only name, resource_id and the rules as unknown-at-plan ids; the rule set is reviewed in the call

  # not-testable: network-security-group__integration.rules.subnet_purpose - the module exposes only name, resource_id and the rules as unknown-at-plan ids; the rule set is reviewed in the call

  # not-testable: network-security-group__integration.rules.default_inbound - the module exposes only name, resource_id and the rules as unknown-at-plan ids; the rule set is reviewed in the call

  # not-testable: network-security-group__integration.rules.default_outbound - the module exposes only name, resource_id and the rules as unknown-at-plan ids; the rule set is reviewed in the call

  # not-testable: network-security-group__integration.rules.rules - the module exposes only name, resource_id and the rules as unknown-at-plan ids; the rule set is reviewed in the call

  # not-testable: network-security-group__containerapps.rules.subnet_purpose - the module exposes only name, resource_id and the rules as unknown-at-plan ids; the rule set is reviewed in the call

  # not-testable: network-security-group__containerapps.rules.default_inbound - the module exposes only name, resource_id and the rules as unknown-at-plan ids; the rule set is reviewed in the call

  # not-testable: network-security-group__containerapps.rules.default_outbound - the module exposes only name, resource_id and the rules as unknown-at-plan ids; the rule set is reviewed in the call

  # not-testable: network-security-group__containerapps.rules.rules - the module exposes only name, resource_id and the rules as unknown-at-plan ids; the rule set is reviewed in the call

  # decision: application-insights.networking.public_network_access
  assert {
    condition     = module.observability.insights.resource.internet_ingestion_enabled == false
    error_message = "application-insights.networking.public_network_access must be false, got ${try(jsonencode(module.observability.insights.resource.internet_ingestion_enabled), "unknown")}."
  }

  # not-testable: key-vault.networking.public_network_access - the key-vault module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: key-vault.networking.private_endpoint_subnet - the private endpoint is a child resource of the module; the root sees only its name

  # not-testable: key-vault.networking.network_acl_bypass - the key-vault module exposes no attribute for it; set through the module input, reviewed in the call

  # decision: storage-account__uploads.networking.public_network_access
  assert {
    condition     = module.data.storage["uploads"].resource.body.properties.publicNetworkAccess == "Disabled"
    error_message = "storage-account__uploads.networking.public_network_access must be \"Disabled\", got ${try(jsonencode(module.data.storage["uploads"].resource.body.properties.publicNetworkAccess), "unknown")}."
  }

  # not-testable: storage-account__uploads.networking.private_endpoint_subnet - the private endpoint is a child resource of the module; the root sees only its name

  # decision: storage-account__uploads.networking.private_endpoint_subresources
  assert {
    condition     = jsonencode(sort(keys(module.data.storage["uploads"].private_endpoints))) == jsonencode(["blob"])
    error_message = "storage-account__uploads.networking.private_endpoint_subresources must be [\"blob\"], got ${try(jsonencode(sort(keys(module.data.storage["uploads"].private_endpoints))), "unknown")}."
  }

  # decision: storage-account__uploads.networking.allow_azure_services_bypass
  assert {
    condition     = module.data.storage["uploads"].resource.body.properties.networkAcls.bypass == "AzureServices"
    error_message = "storage-account__uploads.networking.allow_azure_services_bypass must be \"AzureServices\", got ${try(jsonencode(module.data.storage["uploads"].resource.body.properties.networkAcls.bypass), "unknown")}."
  }

  # decision: storage-account__host.networking.public_network_access
  assert {
    condition     = module.data.storage["host"].resource.body.properties.publicNetworkAccess == "Disabled"
    error_message = "storage-account__host.networking.public_network_access must be \"Disabled\", got ${try(jsonencode(module.data.storage["host"].resource.body.properties.publicNetworkAccess), "unknown")}."
  }

  # not-testable: storage-account__host.networking.private_endpoint_subnet - the private endpoint is a child resource of the module; the root sees only its name

  # decision: storage-account__host.networking.private_endpoint_subresources
  assert {
    condition     = jsonencode(sort(keys(module.data.storage["host"].private_endpoints))) == jsonencode(["blob", "queue", "table"])
    error_message = "storage-account__host.networking.private_endpoint_subresources must be [\"blob\", \"queue\", \"table\"], got ${try(jsonencode(sort(keys(module.data.storage["host"].private_endpoints))), "unknown")}."
  }

  # decision: storage-account__host.networking.allow_azure_services_bypass
  assert {
    condition     = module.data.storage["host"].resource.body.properties.networkAcls.bypass == "AzureServices"
    error_message = "storage-account__host.networking.allow_azure_services_bypass must be \"AzureServices\", got ${try(jsonencode(module.data.storage["host"].resource.body.properties.networkAcls.bypass), "unknown")}."
  }

  # decision: cosmos-db.networking.public_network_access
  assert {
    condition     = module.data.cosmos.public_network_access_enabled == false
    error_message = "cosmos-db.networking.public_network_access must be false, got ${try(jsonencode(module.data.cosmos.public_network_access_enabled), "unknown")}."
  }

  # not-testable: cosmos-db.networking.private_endpoint_subnet - the private endpoint is a child resource of the module; the root sees only its name

  # decision: cosmos-db.networking.network_acl_bypass
  assert {
    condition     = module.data.cosmos.network_acl_bypass_for_azure_services == false
    error_message = "cosmos-db.networking.network_acl_bypass must be false, got ${try(jsonencode(module.data.cosmos.network_acl_bypass_for_azure_services), "unknown")}."
  }

  # decision: foundry.networking.public_network_access
  assert {
    condition     = module.ai.foundry.resource.public_network_access == "Disabled"
    error_message = "foundry.networking.public_network_access must be \"Disabled\", got ${try(jsonencode(module.ai.foundry.resource.public_network_access), "unknown")}."
  }

  # not-testable: foundry.networking.private_endpoint_subnet - the private endpoint is a child resource of the module; the root sees only its name

  # decision: foundry.networking.restrict_outbound
  assert {
    condition     = module.ai.foundry.resource.outbound_network_access_restricted == true
    error_message = "foundry.networking.restrict_outbound must be true, got ${try(jsonencode(module.ai.foundry.resource.outbound_network_access_restricted), "unknown")}."
  }

  # decision: search-service.networking.public_network_access
  assert {
    condition     = module.ai.search.resource.public_network_access_enabled == false
    error_message = "search-service.networking.public_network_access must be false, got ${try(jsonencode(module.ai.search.resource.public_network_access_enabled), "unknown")}."
  }

  # not-testable: search-service.networking.private_endpoint_subnet - the private endpoint is a child resource of the module; the root sees only its name

  # decision: search-service.networking.network_rule_bypass
  assert {
    condition     = module.ai.search.resource.network_rule_bypass_option == "None"
    error_message = "search-service.networking.network_rule_bypass must be \"None\", got ${try(jsonencode(module.ai.search.resource.network_rule_bypass_option), "unknown")}."
  }

  # not-testable: container-registry.networking.public_network_access - the container-registry module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-registry.networking.private_endpoint_subnet - the private endpoint is a child resource of the module; the root sees only its name

  # not-testable: container-registry.networking.network_rule_bypass - the container-registry module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-registry.networking.export_policy_enabled - the container-registry module exposes no attribute for it; set through the module input, reviewed in the call

  # decision: function-app.networking.public_network_access
  assert {
    condition     = module.compute.function.resource.body.properties.publicNetworkAccess == "Disabled"
    error_message = "function-app.networking.public_network_access must be \"Disabled\", got ${try(jsonencode(module.compute.function.resource.body.properties.publicNetworkAccess), "unknown")}."
  }

  # not-testable: function-app.networking.private_endpoint_subnet - the private endpoint is a child resource of the module; the root sees only its name

  # not-testable: function-app.networking.vnet_integration - the integration is the subnet id, unknown at plan time

  # not-testable: function-app.networking.integration_subnet - the subnet id is unknown at plan time

  # decision: function-app.networking.vnet_route_all
  assert {
    condition     = module.compute.function.resource.body.properties.outboundVnetRouting.allTraffic == true
    error_message = "function-app.networking.vnet_route_all must be true, got ${try(jsonencode(module.compute.function.resource.body.properties.outboundVnetRouting.allTraffic), "unknown")}."
  }

  # decision: app-service__web.networking.public_network_access
  assert {
    condition     = module.compute.app["web"].resource.body.properties.publicNetworkAccess == "Disabled"
    error_message = "app-service__web.networking.public_network_access must be \"Disabled\", got ${try(jsonencode(module.compute.app["web"].resource.body.properties.publicNetworkAccess), "unknown")}."
  }

  # not-testable: app-service__web.networking.private_endpoint_subnet - the private endpoint is a child resource of the module; the root sees only its name

  # not-testable: app-service__web.networking.vnet_integration - the integration is the subnet id, unknown at plan time

  # not-testable: app-service__web.networking.integration_subnet - the subnet id is unknown at plan time

  # decision: app-service__web.networking.vnet_route_all
  assert {
    condition     = module.compute.app["web"].resource.body.properties.outboundVnetRouting.allTraffic == true
    error_message = "app-service__web.networking.vnet_route_all must be true, got ${try(jsonencode(module.compute.app["web"].resource.body.properties.outboundVnetRouting.allTraffic), "unknown")}."
  }

  # decision: app-service__mcp.networking.public_network_access
  assert {
    condition     = module.compute.app["mcp"].resource.body.properties.publicNetworkAccess == "Disabled"
    error_message = "app-service__mcp.networking.public_network_access must be \"Disabled\", got ${try(jsonencode(module.compute.app["mcp"].resource.body.properties.publicNetworkAccess), "unknown")}."
  }

  # not-testable: app-service__mcp.networking.private_endpoint_subnet - the private endpoint is a child resource of the module; the root sees only its name

  # not-testable: app-service__mcp.networking.vnet_integration - the integration is the subnet id, unknown at plan time

  # not-testable: app-service__mcp.networking.integration_subnet - the subnet id is unknown at plan time

  # decision: app-service__mcp.networking.vnet_route_all
  assert {
    condition     = module.compute.app["mcp"].resource.body.properties.outboundVnetRouting.allTraffic == true
    error_message = "app-service__mcp.networking.vnet_route_all must be true, got ${try(jsonencode(module.compute.app["mcp"].resource.body.properties.outboundVnetRouting.allTraffic), "unknown")}."
  }

  # not-testable: container-apps.ingress.ingress - the container app module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-apps.ingress.target_port - the container app module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-apps.ingress.allow_insecure - the container app module exposes no attribute for it; set through the module input, reviewed in the call

}
