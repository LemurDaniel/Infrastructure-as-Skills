# observability: plan-only, platform mocked, naming provider real. Mocks and variables repeat in every
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

  # not-testable: key-vault.observability.diagnostic_workspace - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: key-vault.observability.diagnostic_categories - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: key-vault.observability.metrics_enabled - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: storage-account__uploads.observability.diagnostic_workspace - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: storage-account__uploads.observability.diagnostic_categories - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: storage-account__uploads.observability.metrics_enabled - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: storage-account__host.observability.diagnostic_workspace - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: storage-account__host.observability.diagnostic_categories - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: storage-account__host.observability.metrics_enabled - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: cosmos-db.observability.diagnostic_workspace - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: cosmos-db.observability.diagnostic_categories - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: cosmos-db.observability.metrics_enabled - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: foundry.observability.diagnostic_workspace - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: foundry.observability.diagnostic_categories - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: foundry.observability.metrics_enabled - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: search-service.observability.diagnostic_workspace - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: search-service.observability.diagnostic_categories - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: search-service.observability.metrics_enabled - the diagnostic setting is built by the module in a child resource, which the root cannot read

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
