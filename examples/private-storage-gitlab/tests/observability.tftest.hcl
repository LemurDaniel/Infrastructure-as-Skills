# observability: plan-only, platform mocked. Mocks and variables repeat in every file of tests/ -
# terraform test has no include. The intro comment is in naming.tftest.hcl.

mock_provider "azurerm" {
  # The provider validates every referenced id's shape, so the mocked data
  # sources need ids that parse - a random placeholder string does not.
  mock_data "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-invoicing-prod-we"
    }
  }
  mock_data "azurerm_virtual_network" {
    defaults = {
      id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-network-prod-we/providers/Microsoft.Network/virtualNetworks/vnet-hub-prod-we"
    }
  }
  mock_data "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-network-prod-we/providers/Microsoft.Network/virtualNetworks/vnet-hub-prod-we/subnets/snet-privatelink"
    }
  }
  mock_data "azurerm_log_analytics_workspace" {
    defaults = {
      id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-observability-prod-we/providers/Microsoft.OperationalInsights/workspaces/log-platform-prod-we"
    }
  }
}

mock_provider "azapi" {}
mock_provider "modtm" {}

variables {
  environment         = "production"
  location            = "westeurope"
  workload            = "invoicing"
  subscription_id     = "11111111-2222-3333-4444-555555555555"
  resource_group_name = "rg-invoicing-prod-we"

  vnet_name                     = "vnet-hub-prod-we"
  network_resource_group_name   = "rg-network-prod-we"
  private_endpoint_subnet_name  = "snet-privatelink"
  workspace_name                = "log-platform-prod-we"
  workspace_resource_group_name = "rg-observability-prod-we"
  replication                   = "ZRS"
}

run "observability" {
  command = plan

  # The diagnostic settings are child modules of the AVM module; nothing of them reaches
  # an output. The call passes workspace, categories and metrics (storage.tf,
  # diagnostic_settings_storage_account / _blob).
  # not-testable: storage-account.observability.diagnostic_workspace - set through the module's diagnostic_settings_* inputs; the module's own tests cover the mapping
  # not-testable: storage-account.observability.diagnostic_categories - set through the module's diagnostic_settings_blob input; the module's own tests cover the mapping
  # not-testable: storage-account.observability.metrics_enabled - set through the module's diagnostic_settings_* inputs; the module's own tests cover the mapping

  # deployment.module_telemetry: enabled - the module's telemetry resource exists.
  assert {
    condition     = module.storage.resource.create_headers != null
    error_message = "module_telemetry: enabled - the module tags its requests with the AVM header."
  }
}
