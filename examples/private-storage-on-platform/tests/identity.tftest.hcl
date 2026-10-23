# identity: plan-only, platform mocked. Mocks and variables repeat in every file of tests/ -
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

run "identity" {
  command = plan

  # decision: storage-account.identity.managed_identity
  assert {
    condition     = module.storage.resource.identity[0].type == "SystemAssigned"
    error_message = "System-assigned identity."
  }

  # not-testable: storage-account.identity.role_assignments - rendered by the module's
  # role_assignments child module from an empty map; nothing of it reaches an output.
  # The variable is empty and the spec says open, which is the state being asserted.
}
