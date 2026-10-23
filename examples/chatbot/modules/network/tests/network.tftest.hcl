# network: plan-only, run with `terraform -chdir=modules/network test`. The family module is the
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
  address_space         = "10.20.0.0/16"
  subnets = {
    "snet-endpoints" = { prefix = "10.20.0.0/27" }
    "snet-web"       = { prefix = "10.20.0.64/26" }
    "snet-mcp"       = { prefix = "10.20.0.128/26" }
    "snet-func"      = { prefix = "10.20.0.192/26" }
    "snet-aca"       = { prefix = "10.20.1.0/27" }
  }
}

# --- naming ---
run "naming" {
  command = plan

  assert {
    condition     = data.naming_name.network.name == "vnet-we-prod-chatbot-01"
    error_message = "The network name must come from naming.yaml: vnet-we-prod-chatbot-01, got ${data.naming_name.network.name}."
  }
}

# --- networking ---
run "networking" {
  command = plan

  # decision: virtual-network.addressing.address_space
  assert {
    condition     = jsonencode(module.network.resource.body.properties.addressSpace.addressPrefixes) == jsonencode(["10.20.0.0/16"])
    error_message = "virtual-network.addressing.address_space must be [\"10.20.0.0/16\"], got ${try(jsonencode(module.network.resource.body.properties.addressSpace.addressPrefixes), "unknown")}."
  }

  # decision: virtual-network.addressing.subnets
  assert {
    condition     = jsonencode(sort(keys(module.network.subnets))) == jsonencode(["snet-aca", "snet-endpoints", "snet-func", "snet-mcp", "snet-web"])
    error_message = "virtual-network.addressing.subnets must be [\"snet-aca\", \"snet-endpoints\", \"snet-func\", \"snet-mcp\", \"snet-web\"], got ${try(jsonencode(sort(keys(module.network.subnets))), "unknown")}."
  }

  # not-testable: virtual-network.addressing.private_endpoint_subnet_prefix - the subnet is a child resource of the module, which the root cannot read

  # decision: virtual-network.addressing.dns_servers
  assert {
    condition     = module.network.resource.body.properties.dhcpOptions == null
    error_message = "virtual-network.addressing.dns_servers must be null, got ${try(jsonencode(module.network.resource.body.properties.dhcpOptions), "unknown")}."
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
}

# --- observability ---
run "observability" {
  command = plan

  # not-testable: virtual-network.observability.diagnostic_workspace - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: virtual-network.observability.flow_logs_enabled - the subnet is a child resource of the module, which the root cannot read

  # not-testable: network-security-group__endpoints.observability.diagnostic_workspace - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: network-security-group__endpoints.observability.diagnostic_categories - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: network-security-group__integration.observability.diagnostic_workspace - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: network-security-group__integration.observability.diagnostic_categories - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: network-security-group__containerapps.observability.diagnostic_workspace - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: network-security-group__containerapps.observability.diagnostic_categories - the diagnostic setting is built by the module in a child resource, which the root cannot read
}

# --- security ---
run "security" {
  command = plan

  # decision: virtual-network.security.ddos_protection
  assert {
    condition     = module.network.resource.body.properties.enableDdosProtection == false
    error_message = "virtual-network.security.ddos_protection must be false, got ${try(jsonencode(module.network.resource.body.properties.enableDdosProtection), "unknown")}."
  }

  # not-testable: virtual-network.security.subnets_expecting_nsg - the subnet is a child resource of the module, which the root cannot read
}
