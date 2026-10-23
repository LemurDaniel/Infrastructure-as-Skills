# data: plan-only, run with `terraform -chdir=modules/data test`. The family module is the
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
  subnet_ids = {
    "snet-endpoints" = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.Network/virtualNetworks/vnet-we-prod-chatbot-01/subnets/snet-endpoints"
    "snet-web"       = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.Network/virtualNetworks/vnet-we-prod-chatbot-01/subnets/snet-web"
    "snet-mcp"       = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.Network/virtualNetworks/vnet-we-prod-chatbot-01/subnets/snet-mcp"
    "snet-func"      = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.Network/virtualNetworks/vnet-we-prod-chatbot-01/subnets/snet-func"
    "snet-aca"       = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.Network/virtualNetworks/vnet-we-prod-chatbot-01/subnets/snet-aca"
  }
  role_assignments_uai         = {}
  role_assignments_search      = {}
  uai_principal_ids            = {}
  cosmos_data_role_assignments = []
}

# --- compute ---
run "compute" {
  command = plan

  # not-testable: cosmos-db.account.capacity_mode - a container- or region-level setting inside the module's nested inputs, not exposed as an output

  # not-testable: cosmos-db.account.throughput_mode - a container- or region-level setting inside the module's nested inputs, not exposed as an output

  # not-testable: cosmos-db.account.max_throughput - a container- or region-level setting inside the module's nested inputs, not exposed as an output

  # decision: cosmos-db.account.total_throughput_limit
  assert {
    condition     = module.cosmos.capacity.total_throughput_limit == -1
    error_message = "cosmos-db.account.total_throughput_limit must be -1, got ${try(jsonencode(module.cosmos.capacity.total_throughput_limit), "unknown")}."
  }

  # decision: cosmos-db.account.free_tier
  assert {
    condition     = module.cosmos.free_tier_enabled == false
    error_message = "cosmos-db.account.free_tier must be false, got ${try(jsonencode(module.cosmos.free_tier_enabled), "unknown")}."
  }

  # not-testable: cosmos-db.resilience.zone_redundant - a container- or region-level setting inside the module's nested inputs, not exposed as an output

  # not-testable: cosmos-db.resilience.geo_replicas - a container- or region-level setting inside the module's nested inputs, not exposed as an output

  # decision: cosmos-db.resilience.automatic_failover
  assert {
    condition     = module.cosmos.automatic_failover_enabled == true
    error_message = "cosmos-db.resilience.automatic_failover must be true, got ${try(jsonencode(module.cosmos.automatic_failover_enabled), "unknown")}."
  }

  # decision: cosmos-db.resilience.consistency_level
  assert {
    condition     = module.cosmos.consistency_policy.consistency_level == "Session"
    error_message = "cosmos-db.resilience.consistency_level must be \"Session\", got ${try(jsonencode(module.cosmos.consistency_policy.consistency_level), "unknown")}."
  }
}

# --- data_protection ---
run "data_protection" {
  command = plan

  # decision: storage-account__uploads.data_protection.replication
  assert {
    condition     = module.storage["uploads"].resource.body.sku.name == "Standard_ZRS"
    error_message = "storage-account__uploads.data_protection.replication must be \"Standard_ZRS\", got ${try(jsonencode(module.storage["uploads"].resource.body.sku.name), "unknown")}."
  }

  # decision: storage-account__uploads.data_protection.access_tier
  assert {
    condition     = module.storage["uploads"].resource.body.properties.accessTier == "Hot"
    error_message = "storage-account__uploads.data_protection.access_tier must be \"Hot\", got ${try(jsonencode(module.storage["uploads"].resource.body.properties.accessTier), "unknown")}."
  }

  # not-testable: storage-account__uploads.data_protection.blob_soft_delete_days - blob-service properties are built in the module's blob_service child, which the root cannot read

  # not-testable: storage-account__uploads.data_protection.container_soft_delete_days - blob-service properties are built in the module's blob_service child, which the root cannot read

  # not-testable: storage-account__uploads.data_protection.versioning_enabled - blob-service properties are built in the module's blob_service child, which the root cannot read

  # not-testable: storage-account__uploads.data_protection.change_feed_enabled - blob-service properties are built in the module's blob_service child, which the root cannot read

  # not-testable: storage-account__uploads.data_protection.point_in_time_restore_days - blob-service properties are built in the module's blob_service child, which the root cannot read

  # not-testable: storage-account__uploads.data_protection.immutability - blob-service properties are built in the module's blob_service child, which the root cannot read

  # decision: storage-account__host.data_protection.replication
  assert {
    condition     = module.storage["host"].resource.body.sku.name == "Standard_ZRS"
    error_message = "storage-account__host.data_protection.replication must be \"Standard_ZRS\", got ${try(jsonencode(module.storage["host"].resource.body.sku.name), "unknown")}."
  }

  # decision: storage-account__host.data_protection.access_tier
  assert {
    condition     = module.storage["host"].resource.body.properties.accessTier == "Hot"
    error_message = "storage-account__host.data_protection.access_tier must be \"Hot\", got ${try(jsonencode(module.storage["host"].resource.body.properties.accessTier), "unknown")}."
  }

  # not-testable: storage-account__host.data_protection.blob_soft_delete_days - blob-service properties are built in the module's blob_service child, which the root cannot read

  # not-testable: storage-account__host.data_protection.container_soft_delete_days - blob-service properties are built in the module's blob_service child, which the root cannot read

  # not-testable: storage-account__host.data_protection.versioning_enabled - blob-service properties are built in the module's blob_service child, which the root cannot read

  # not-testable: storage-account__host.data_protection.change_feed_enabled - blob-service properties are built in the module's blob_service child, which the root cannot read

  # not-testable: storage-account__host.data_protection.point_in_time_restore_days - blob-service properties are built in the module's blob_service child, which the root cannot read

  # not-testable: storage-account__host.data_protection.immutability - blob-service properties are built in the module's blob_service child, which the root cannot read

  # not-testable: cosmos-db.data_protection.backup_policy - a container- or region-level setting inside the module's nested inputs, not exposed as an output

  # decision: cosmos-db.data_protection.analytical_storage
  assert {
    condition     = module.cosmos.analytical_storage_enabled == false
    error_message = "cosmos-db.data_protection.analytical_storage must be false, got ${try(jsonencode(module.cosmos.analytical_storage_enabled), "unknown")}."
  }

  # not-testable: cosmos-db.containers.databases - a container- or region-level setting inside the module's nested inputs, not exposed as an output
}

# --- identity ---
run "identity" {
  command = plan

  # not-testable: storage-account__uploads.identity.managed_identity - the identity assignment is a child of the module call; the root cannot read it back

  # not-testable: storage-account__uploads.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read

  # not-testable: storage-account__host.identity.managed_identity - the identity assignment is a child of the module call; the root cannot read it back

  # not-testable: storage-account__host.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read

  # not-testable: cosmos-db.identity.managed_identity - a container- or region-level setting inside the module's nested inputs, not exposed as an output

  # not-testable: cosmos-db.identity.data_plane_role_assignments - the role assignments are child resources of the module, which the root cannot read

  # not-testable: cosmos-db.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read
}

# --- naming ---
run "naming" {
  command = plan

  assert {
    condition     = data.naming_name.storage_account["uploads"].name == "stweprodchatbotuploads01"
    error_message = "The storage account for uploads name must come from naming.yaml: stweprodchatbotuploads01, got ${data.naming_name.storage_account["uploads"].name}."
  }

  assert {
    condition     = data.naming_name.storage_account["host"].name == "stweprodchatbothost01"
    error_message = "The storage account for the host name must come from naming.yaml: stweprodchatbothost01, got ${data.naming_name.storage_account["host"].name}."
  }

  # The AzAPI-based modules take the group as an id, not a name - the wrong one is a silent misplacement.
  assert {
    condition     = module.storage["uploads"].resource.parent_id == var.resource_group_id
    error_message = "The storage account is placed into the context's resource group."
  }
}

# --- networking ---
run "networking" {
  command = plan

  # decision: storage-account__uploads.networking.public_network_access
  assert {
    condition     = module.storage["uploads"].resource.body.properties.publicNetworkAccess == "Disabled"
    error_message = "storage-account__uploads.networking.public_network_access must be \"Disabled\", got ${try(jsonencode(module.storage["uploads"].resource.body.properties.publicNetworkAccess), "unknown")}."
  }

  # not-testable: storage-account__uploads.networking.private_endpoint_subnet - the private endpoint is a child resource of the module; the root sees only its name

  # decision: storage-account__uploads.networking.private_endpoint_subresources
  assert {
    condition     = jsonencode(sort(keys(module.storage["uploads"].private_endpoints))) == jsonencode(["blob"])
    error_message = "storage-account__uploads.networking.private_endpoint_subresources must be [\"blob\"], got ${try(jsonencode(sort(keys(module.storage["uploads"].private_endpoints))), "unknown")}."
  }

  # decision: storage-account__uploads.networking.allow_azure_services_bypass
  assert {
    condition     = module.storage["uploads"].resource.body.properties.networkAcls.bypass == "AzureServices"
    error_message = "storage-account__uploads.networking.allow_azure_services_bypass must be \"AzureServices\", got ${try(jsonencode(module.storage["uploads"].resource.body.properties.networkAcls.bypass), "unknown")}."
  }

  # decision: storage-account__host.networking.public_network_access
  assert {
    condition     = module.storage["host"].resource.body.properties.publicNetworkAccess == "Disabled"
    error_message = "storage-account__host.networking.public_network_access must be \"Disabled\", got ${try(jsonencode(module.storage["host"].resource.body.properties.publicNetworkAccess), "unknown")}."
  }

  # not-testable: storage-account__host.networking.private_endpoint_subnet - the private endpoint is a child resource of the module; the root sees only its name

  # decision: storage-account__host.networking.private_endpoint_subresources
  assert {
    condition     = jsonencode(sort(keys(module.storage["host"].private_endpoints))) == jsonencode(["blob", "queue", "table"])
    error_message = "storage-account__host.networking.private_endpoint_subresources must be [\"blob\", \"queue\", \"table\"], got ${try(jsonencode(sort(keys(module.storage["host"].private_endpoints))), "unknown")}."
  }

  # decision: storage-account__host.networking.allow_azure_services_bypass
  assert {
    condition     = module.storage["host"].resource.body.properties.networkAcls.bypass == "AzureServices"
    error_message = "storage-account__host.networking.allow_azure_services_bypass must be \"AzureServices\", got ${try(jsonencode(module.storage["host"].resource.body.properties.networkAcls.bypass), "unknown")}."
  }

  # decision: cosmos-db.networking.public_network_access
  assert {
    condition     = module.cosmos.public_network_access_enabled == false
    error_message = "cosmos-db.networking.public_network_access must be false, got ${try(jsonencode(module.cosmos.public_network_access_enabled), "unknown")}."
  }

  # not-testable: cosmos-db.networking.private_endpoint_subnet - the private endpoint is a child resource of the module; the root sees only its name

  # decision: cosmos-db.networking.network_acl_bypass
  assert {
    condition     = module.cosmos.network_acl_bypass_for_azure_services == false
    error_message = "cosmos-db.networking.network_acl_bypass must be false, got ${try(jsonencode(module.cosmos.network_acl_bypass_for_azure_services), "unknown")}."
  }
}

# --- observability ---
run "observability" {
  command = plan

  # not-testable: storage-account__uploads.observability.diagnostic_workspace - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: storage-account__uploads.observability.diagnostic_categories - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: storage-account__uploads.observability.metrics_enabled - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: storage-account__host.observability.diagnostic_workspace - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: storage-account__host.observability.diagnostic_categories - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: storage-account__host.observability.metrics_enabled - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: cosmos-db.observability.diagnostic_workspace - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: cosmos-db.observability.diagnostic_categories - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: cosmos-db.observability.metrics_enabled - the diagnostic setting is built by the module in a child resource, which the root cannot read
}

# --- security ---
run "security" {
  command = plan

  # decision: storage-account__uploads.security.shared_access_key_enabled
  assert {
    condition     = module.storage["uploads"].resource.body.properties.allowSharedKeyAccess == false
    error_message = "storage-account__uploads.security.shared_access_key_enabled must be false, got ${try(jsonencode(module.storage["uploads"].resource.body.properties.allowSharedKeyAccess), "unknown")}."
  }

  # decision: storage-account__uploads.security.min_tls_version
  assert {
    condition     = module.storage["uploads"].resource.body.properties.minimumTlsVersion == "TLS1_2"
    error_message = "storage-account__uploads.security.min_tls_version must be \"TLS1_2\", got ${try(jsonencode(module.storage["uploads"].resource.body.properties.minimumTlsVersion), "unknown")}."
  }

  # decision: storage-account__uploads.security.https_traffic_only
  assert {
    condition     = module.storage["uploads"].resource.body.properties.supportsHttpsTrafficOnly == true
    error_message = "storage-account__uploads.security.https_traffic_only must be true, got ${try(jsonencode(module.storage["uploads"].resource.body.properties.supportsHttpsTrafficOnly), "unknown")}."
  }

  # decision: storage-account__uploads.security.allow_blob_public_access
  assert {
    condition     = module.storage["uploads"].resource.body.properties.allowBlobPublicAccess == false
    error_message = "storage-account__uploads.security.allow_blob_public_access must be false, got ${try(jsonencode(module.storage["uploads"].resource.body.properties.allowBlobPublicAccess), "unknown")}."
  }

  # decision: storage-account__uploads.security.infrastructure_encryption_enabled
  assert {
    condition     = module.storage["uploads"].resource.body.properties.encryption.requireInfrastructureEncryption == true
    error_message = "storage-account__uploads.security.infrastructure_encryption_enabled must be true, got ${try(jsonencode(module.storage["uploads"].resource.body.properties.encryption.requireInfrastructureEncryption), "unknown")}."
  }

  # decision: storage-account__uploads.security.key_management
  assert {
    condition     = module.storage["uploads"].resource.body.properties.encryption.keySource == "Microsoft.Storage"
    error_message = "storage-account__uploads.security.key_management must be \"Microsoft.Storage\", got ${try(jsonencode(module.storage["uploads"].resource.body.properties.encryption.keySource), "unknown")}."
  }

  # decision: storage-account__uploads.security.sftp_enabled
  assert {
    condition     = module.storage["uploads"].resource.body.properties.isSftpEnabled == false
    error_message = "storage-account__uploads.security.sftp_enabled must be false, got ${try(jsonencode(module.storage["uploads"].resource.body.properties.isSftpEnabled), "unknown")}."
  }

  # decision: storage-account__host.security.shared_access_key_enabled
  assert {
    condition     = module.storage["host"].resource.body.properties.allowSharedKeyAccess == false
    error_message = "storage-account__host.security.shared_access_key_enabled must be false, got ${try(jsonencode(module.storage["host"].resource.body.properties.allowSharedKeyAccess), "unknown")}."
  }

  # decision: storage-account__host.security.min_tls_version
  assert {
    condition     = module.storage["host"].resource.body.properties.minimumTlsVersion == "TLS1_2"
    error_message = "storage-account__host.security.min_tls_version must be \"TLS1_2\", got ${try(jsonencode(module.storage["host"].resource.body.properties.minimumTlsVersion), "unknown")}."
  }

  # decision: storage-account__host.security.https_traffic_only
  assert {
    condition     = module.storage["host"].resource.body.properties.supportsHttpsTrafficOnly == true
    error_message = "storage-account__host.security.https_traffic_only must be true, got ${try(jsonencode(module.storage["host"].resource.body.properties.supportsHttpsTrafficOnly), "unknown")}."
  }

  # decision: storage-account__host.security.allow_blob_public_access
  assert {
    condition     = module.storage["host"].resource.body.properties.allowBlobPublicAccess == false
    error_message = "storage-account__host.security.allow_blob_public_access must be false, got ${try(jsonencode(module.storage["host"].resource.body.properties.allowBlobPublicAccess), "unknown")}."
  }

  # decision: storage-account__host.security.infrastructure_encryption_enabled
  assert {
    condition     = module.storage["host"].resource.body.properties.encryption.requireInfrastructureEncryption == true
    error_message = "storage-account__host.security.infrastructure_encryption_enabled must be true, got ${try(jsonencode(module.storage["host"].resource.body.properties.encryption.requireInfrastructureEncryption), "unknown")}."
  }

  # decision: storage-account__host.security.key_management
  assert {
    condition     = module.storage["host"].resource.body.properties.encryption.keySource == "Microsoft.Storage"
    error_message = "storage-account__host.security.key_management must be \"Microsoft.Storage\", got ${try(jsonencode(module.storage["host"].resource.body.properties.encryption.keySource), "unknown")}."
  }

  # decision: storage-account__host.security.sftp_enabled
  assert {
    condition     = module.storage["host"].resource.body.properties.isSftpEnabled == false
    error_message = "storage-account__host.security.sftp_enabled must be false, got ${try(jsonencode(module.storage["host"].resource.body.properties.isSftpEnabled), "unknown")}."
  }

  # decision: cosmos-db.security.local_authentication_disabled
  assert {
    condition     = module.cosmos.local_authentication_disabled == true
    error_message = "cosmos-db.security.local_authentication_disabled must be true, got ${try(jsonencode(module.cosmos.local_authentication_disabled), "unknown")}."
  }

  # decision: cosmos-db.security.key_based_metadata_writes
  assert {
    condition     = module.cosmos.access_key_metadata_writes_enabled == false
    error_message = "cosmos-db.security.key_based_metadata_writes must be false, got ${try(jsonencode(module.cosmos.access_key_metadata_writes_enabled), "unknown")}."
  }

  # not-testable: cosmos-db.security.key_management - platform-managed keys: the module is given no key, nothing to observe
}
