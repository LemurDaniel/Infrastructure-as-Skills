# Plan-only, so it needs no credentials. The platform is referenced through data
# sources, which a real plan would have to read from Azure - the mock provider
# answers them with placeholder values instead. The naming provider stays real,
# so rendered names are asserted as they will be deployed.
#
# Every decision under resources: in ../infra-spec.yaml is asserted exactly once,
# named by its key path in a `# decision:` comment; what a plan cannot observe is
# marked `# not-testable:` with its reason. Test-RenderCoverage.ps1 checks both.
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

run "naming" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.name == "stweprodinvoicing01"
    error_message = "Storage account name must come from naming.yaml: stweprodinvoicing01."
  }

  assert {
    condition     = azurerm_private_endpoint.storage["blob"].name == "pep-we-prod-invoicing-blob-01"
    error_message = "Private endpoint name must come from naming.yaml, <?SUBNAME> before the index."
  }
}

run "networking" {
  command = plan

  # decision: storage-account.networking.public_network_access
  assert {
    condition     = azurerm_storage_account.this.public_network_access == "Disabled" && length(azurerm_storage_account.this.network_rules) == 0
    error_message = "Private: no public endpoint, and no ACL that would suggest one."
  }

  # decision: storage-account.networking.private_endpoint_subnet
  assert {
    condition     = azurerm_private_endpoint.storage["blob"].subnet_id == data.azurerm_subnet.private_endpoints.id
    error_message = "The endpoint goes into the platform's private-endpoint subnet."
  }

  # decision: storage-account.networking.private_endpoint_subresources
  assert {
    condition     = length(azurerm_private_endpoint.storage) == 1 && azurerm_private_endpoint.storage["blob"].private_service_connection[0].subresource_names[0] == "blob"
    error_message = "One endpoint per listed sub-resource, blob only."
  }

  # not-testable: storage-account.networking.allow_azure_services_bypass - network_rules
  # is not rendered with public access disabled; nothing in the plan carries the bypass

  # deployment.private_dns_records: policy
  assert {
    condition     = length(azurerm_private_endpoint.storage["blob"].private_dns_zone_group) == 0
    error_message = "private_dns_records: policy - the platform writes the record, not this code."
  }
}

run "identity" {
  command = plan

  # decision: storage-account.identity.managed_identity
  assert {
    condition     = azurerm_storage_account.this.identity[0].type == "SystemAssigned"
    error_message = "System-assigned identity."
  }

  # decision: storage-account.identity.role_assignments
  assert {
    condition     = length(azurerm_role_assignment.data) == 0
    error_message = "No consumer named yet, so no assignment - open in the spec."
  }
}

run "security" {
  command = plan

  # decision: storage-account.security.shared_access_key_enabled
  assert {
    condition     = azurerm_storage_account.this.shared_access_key_enabled == false
    error_message = "Shared key auth must stay off; access is via Entra ID and RBAC."
  }

  # decision: storage-account.security.min_tls_version
  assert {
    condition     = azurerm_storage_account.this.min_tls_version == "TLS1_2"
    error_message = "TLS 1.2 is the floor."
  }

  # decision: storage-account.security.https_traffic_only
  assert {
    condition     = azurerm_storage_account.this.https_traffic_only_enabled == true
    error_message = "No plain HTTP."
  }

  # decision: storage-account.security.allow_blob_public_access
  assert {
    condition     = azurerm_storage_account.this.allow_nested_items_to_be_public == false
    error_message = "Anonymous container access must not be possible at the account level."
  }

  # decision: storage-account.security.infrastructure_encryption_enabled
  assert {
    condition     = azurerm_storage_account.this.infrastructure_encryption_enabled == true
    error_message = "Infrastructure encryption is settable only at creation and must be on."
  }

  # decision: storage-account.security.key_management
  assert {
    condition     = length(azurerm_storage_account.this.customer_managed_key) == 0
    error_message = "Platform-managed keys: no CMK block."
  }

  # decision: storage-account.security.sftp_enabled
  assert {
    condition     = azurerm_storage_account.this.sftp_enabled == false
    error_message = "SFTP brings local users - credentials outside Entra ID."
  }
}

run "data_protection" {
  command = plan

  # decision: storage-account.data_protection.replication
  assert {
    condition     = azurerm_storage_account.this.account_replication_type == "ZRS"
    error_message = "ZRS: survives a zone loss at roughly LRS cost."
  }

  # decision: storage-account.data_protection.access_tier
  assert {
    condition     = azurerm_storage_account.this.access_tier == "Hot"
    error_message = "Hot tier by default."
  }

  # decision: storage-account.data_protection.blob_soft_delete_days
  assert {
    condition     = azurerm_storage_account.this.blob_properties[0].delete_retention_policy[0].days == 7
    error_message = "Blob soft delete 7 days."
  }

  # decision: storage-account.data_protection.container_soft_delete_days
  assert {
    condition     = azurerm_storage_account.this.blob_properties[0].container_delete_retention_policy[0].days == 7
    error_message = "Container soft delete 7 days."
  }

  # decision: storage-account.data_protection.versioning_enabled
  assert {
    condition     = azurerm_storage_account.this.blob_properties[0].versioning_enabled == true
    error_message = "Versioning on: protects against overwrite, which soft delete does not."
  }

  # decision: storage-account.data_protection.change_feed_enabled
  assert {
    condition     = azurerm_storage_account.this.blob_properties[0].change_feed_enabled == false
    error_message = "Change feed off unless something consumes it."
  }

  # decision: storage-account.data_protection.point_in_time_restore_days
  assert {
    condition     = length(azurerm_storage_account.this.blob_properties[0].restore_policy) == 0
    error_message = "Point-in-time restore off: no restore_policy block."
  }

  # decision: storage-account.data_protection.immutability
  assert {
    condition     = length(azurerm_storage_account.this.immutability_policy) == 0
    error_message = "No WORM policy unless a mandate names one."
  }
}

run "observability" {
  command = plan

  # decision: storage-account.observability.diagnostic_workspace
  assert {
    condition     = azurerm_monitor_diagnostic_setting.storage.log_analytics_workspace_id == data.azurerm_log_analytics_workspace.platform.id && azurerm_monitor_diagnostic_setting.storage_blob.log_analytics_workspace_id == data.azurerm_log_analytics_workspace.platform.id
    error_message = "Both settings route to the platform workspace."
  }

  # decision: storage-account.observability.diagnostic_categories
  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.storage_blob.enabled_log) == 1 && contains([for l in azurerm_monitor_diagnostic_setting.storage_blob.enabled_log : l.category_group], "audit")
    error_message = "audit on the blob service, and nothing else in production."
  }

  # decision: storage-account.observability.metrics_enabled
  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.storage.enabled_metric) == 1 && length(azurerm_monitor_diagnostic_setting.storage_blob.enabled_metric) == 1
    error_message = "AllMetrics on both targets."
  }
}
