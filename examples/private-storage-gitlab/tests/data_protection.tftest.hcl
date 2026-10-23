# data_protection: plan-only, platform mocked. Mocks and variables repeat in every file of tests/ -
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

run "data_protection" {
  command = plan

  # decision: storage-account.data_protection.replication
  assert {
    condition     = module.storage.resource.body.sku.name == "Standard_ZRS"
    error_message = "ZRS: survives a zone loss at roughly LRS cost."
  }

  # decision: storage-account.data_protection.access_tier
  assert {
    condition     = module.storage.resource.body.properties.accessTier == "Hot"
    error_message = "Hot tier by default."
  }

  # decision: storage-account.data_protection.immutability
  assert {
    condition     = module.storage.resource.body.properties.immutableStorageWithVersioning == null
    error_message = "No WORM policy unless a mandate names one."
  }

  # The blob service is a child module of the AVM module; its azapi body is not reachable
  # from a test of this root. The call passes the values (storage.tf, blob_properties);
  # the module's own tests cover blob_properties -> blobServices/default.
  # not-testable: storage-account.data_protection.blob_soft_delete_days - set through the module's blob_properties input; the module's own tests cover the mapping
  # not-testable: storage-account.data_protection.container_soft_delete_days - set through the module's blob_properties input; the module's own tests cover the mapping
  # not-testable: storage-account.data_protection.versioning_enabled - set through the module's blob_properties input; the module's own tests cover the mapping
  # not-testable: storage-account.data_protection.change_feed_enabled - set through the module's blob_properties input; the module's own tests cover the mapping
  # not-testable: storage-account.data_protection.point_in_time_restore_days - set through the module's blob_properties input (absent restore_policy); the module's own tests cover the mapping
}
