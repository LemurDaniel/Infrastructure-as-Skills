# networking: plan-only, platform mocked. Mocks and variables repeat in every file of tests/ -
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

run "networking" {
  command = plan

  # decision: storage-account.networking.public_network_access
  assert {
    condition     = module.storage.resource.body.properties.publicNetworkAccess == "Disabled"
    error_message = "Private: the module must send publicNetworkAccess Disabled."
  }

  # decision: storage-account.networking.allow_azure_services_bypass
  assert {
    condition     = module.storage.resource.body.properties.networkAcls.defaultAction == "Deny" && module.storage.resource.body.properties.networkAcls.bypass == "AzureServices"
    error_message = "The ACL documents the posture: default Deny, trusted Azure services bypass."
  }

  # not-testable: storage-account.networking.private_endpoint_subnet - the subnet id is an
  # input to the module's private_endpoint child module, whose azapi body the root cannot
  # reach; the module's own tests cover subnet_resource_id -> properties.subnet.id
  # decision: storage-account.networking.private_endpoint_subresources
  assert {
    condition     = length(module.storage.private_endpoints) == 1 && contains(keys(module.storage.private_endpoints), "blob")
    error_message = "One endpoint per listed sub-resource, blob only."
  }

  # deployment.private_dns_records: policy - with manage_dns_zone_group false the module
  # renders no zone group, and its id comes back null rather than unknown.
  assert {
    condition     = module.storage.private_endpoints["blob"].private_dns_zone_group_id == null
    error_message = "private_dns_records: policy - the platform writes the record, not this code."
  }
}
