# Plan-only, so it needs no credentials. The platform is referenced through data
# sources, which a real plan would have to read from Azure - the mock provider
# answers them with placeholder values instead. The AVM module plans against a
# mocked azapi and modtm the same way; the naming provider stays real, so
# rendered names are asserted as they will be deployed.
#
# Every decision under resources: in ../infra-spec.yaml is asserted exactly once,
# named by its key path in a `# decision:` comment; what a plan cannot observe is
# marked `# not-testable:` with its reason. check_render_coverage.py checks both.
#
# With a module in the middle the assert target is the module's `resource` output:
# the azapi_resource the module creates, whose `body` is what this root passed in
# and is known at plan time. Sub-resources the module creates in its own child
# modules (blob service, diagnostic settings, role assignments) are not reachable
# from a test of the root - those decisions lean on the module's own tests.
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
}

run "naming" {
  command = plan

  assert {
    condition     = module.storage.resource.name == "stweprodinvoicing01"
    error_message = "Storage account name must come from naming.yaml: stweprodinvoicing01."
  }

  assert {
    condition     = module.storage.private_endpoints["blob"].name == "pep-we-prod-invoicing-blob-01"
    error_message = "Private endpoint name must come from naming.yaml, <?SUBNAME> before the index."
  }

  # The module takes the group as an id, not a name - the wrong one is a silent misplacement.
  assert {
    condition     = module.storage.resource.parent_id == data.azurerm_resource_group.this.id
    error_message = "The account is placed into the context's resource group."
  }
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
