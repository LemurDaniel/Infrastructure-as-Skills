# security: plan-only, platform mocked. Mocks and variables repeat in every file of tests/ -
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

run "security" {
  command = plan

  # decision: storage-account.security.shared_access_key_enabled
  assert {
    condition     = module.storage.resource.body.properties.allowSharedKeyAccess == false
    error_message = "Shared key auth must stay off; access is via Entra ID and RBAC."
  }

  # decision: storage-account.security.min_tls_version
  assert {
    condition     = module.storage.resource.body.properties.minimumTlsVersion == "TLS1_2"
    error_message = "TLS 1.2 is the floor."
  }

  # decision: storage-account.security.https_traffic_only
  assert {
    condition     = module.storage.resource.body.properties.supportsHttpsTrafficOnly == true
    error_message = "No plain HTTP."
  }

  # decision: storage-account.security.allow_blob_public_access
  assert {
    condition     = module.storage.resource.body.properties.allowBlobPublicAccess == false
    error_message = "Anonymous container access must not be possible at the account level."
  }

  # decision: storage-account.security.infrastructure_encryption_enabled
  assert {
    condition     = module.storage.resource.body.properties.encryption.requireInfrastructureEncryption == true
    error_message = "Infrastructure encryption is settable only at creation and must be on."
  }

  # decision: storage-account.security.key_management
  assert {
    condition     = module.storage.resource.body.properties.encryption.keySource == "Microsoft.Storage"
    error_message = "Platform-managed keys: keySource Microsoft.Storage, no Key Vault reference."
  }

  # decision: storage-account.security.sftp_enabled
  assert {
    condition     = module.storage.resource.body.properties.isSftpEnabled == false
    error_message = "SFTP brings local users - credentials outside Entra ID."
  }
}
