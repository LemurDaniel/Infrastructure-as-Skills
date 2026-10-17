# Plan-only, so it needs no credentials. The platform is referenced through data
# sources, which a real plan would have to read from Azure - the mock provider
# answers them with placeholder values instead. The naming provider stays real,
# so rendered names are asserted as they will be deployed.
mock_provider "azurerm" {
  # The provider validates every referenced id's shape, so the mocked data
  # sources need ids that parse - a random placeholder string does not.
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
}

run "account_is_private_and_keyless" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.public_network_access == "Disabled"
    error_message = "The account must not be reachable from the public internet."
  }

  assert {
    condition     = azurerm_storage_account.this.shared_access_key_enabled == false
    error_message = "Shared key auth must stay off; access is via Entra ID and RBAC."
  }

  assert {
    condition     = azurerm_storage_account.this.allow_nested_items_to_be_public == false
    error_message = "Anonymous container access must not be possible at the account level."
  }

  assert {
    condition     = azurerm_storage_account.this.infrastructure_encryption_enabled == true
    error_message = "Infrastructure encryption is settable only at creation and must be on."
  }
}

run "name_follows_the_convention" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.name == "stweprodinvoicing01"
    error_message = "Storage account name must come from naming.yaml: stweprodinvoicing01."
  }

  assert {
    condition     = azurerm_private_endpoint.storage["blob"].name == "pep-we-prod-invoicing-01-blob"
    error_message = "Private endpoint name must come from naming.yaml."
  }
}

run "no_dns_zone_group_under_policy" {
  command = plan

  assert {
    condition     = length(azurerm_private_endpoint.storage["blob"].private_dns_zone_group) == 0
    error_message = "private_dns_records: policy - the platform writes the record, not this code."
  }
}
