# security: plan-only, platform mocked, naming provider real. Mocks and variables repeat in every
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

run "security" {
  command = plan

  # decision: virtual-network.security.ddos_protection
  assert {
    condition     = module.network.network.resource.body.properties.enableDdosProtection == false
    error_message = "virtual-network.security.ddos_protection must be false, got ${try(jsonencode(module.network.network.resource.body.properties.enableDdosProtection), "unknown")}."
  }

  # not-testable: virtual-network.security.subnets_expecting_nsg - the subnet is a child resource of the module, which the root cannot read

  # decision: application-insights.security.local_authentication_disabled
  assert {
    condition     = module.observability.insights.resource.local_authentication_disabled == true
    error_message = "application-insights.security.local_authentication_disabled must be true, got ${try(jsonencode(module.observability.insights.resource.local_authentication_disabled), "unknown")}."
  }

  # not-testable: key-vault.security.enabled_for_services - the key-vault module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: key-vault.security.secret_placeholders - the key-vault module exposes no attribute for it; set through the module input, reviewed in the call

  # decision: storage-account__uploads.security.shared_access_key_enabled
  assert {
    condition     = module.data.storage["uploads"].resource.body.properties.allowSharedKeyAccess == false
    error_message = "storage-account__uploads.security.shared_access_key_enabled must be false, got ${try(jsonencode(module.data.storage["uploads"].resource.body.properties.allowSharedKeyAccess), "unknown")}."
  }

  # decision: storage-account__uploads.security.min_tls_version
  assert {
    condition     = module.data.storage["uploads"].resource.body.properties.minimumTlsVersion == "TLS1_2"
    error_message = "storage-account__uploads.security.min_tls_version must be \"TLS1_2\", got ${try(jsonencode(module.data.storage["uploads"].resource.body.properties.minimumTlsVersion), "unknown")}."
  }

  # decision: storage-account__uploads.security.https_traffic_only
  assert {
    condition     = module.data.storage["uploads"].resource.body.properties.supportsHttpsTrafficOnly == true
    error_message = "storage-account__uploads.security.https_traffic_only must be true, got ${try(jsonencode(module.data.storage["uploads"].resource.body.properties.supportsHttpsTrafficOnly), "unknown")}."
  }

  # decision: storage-account__uploads.security.allow_blob_public_access
  assert {
    condition     = module.data.storage["uploads"].resource.body.properties.allowBlobPublicAccess == false
    error_message = "storage-account__uploads.security.allow_blob_public_access must be false, got ${try(jsonencode(module.data.storage["uploads"].resource.body.properties.allowBlobPublicAccess), "unknown")}."
  }

  # decision: storage-account__uploads.security.infrastructure_encryption_enabled
  assert {
    condition     = module.data.storage["uploads"].resource.body.properties.encryption.requireInfrastructureEncryption == true
    error_message = "storage-account__uploads.security.infrastructure_encryption_enabled must be true, got ${try(jsonencode(module.data.storage["uploads"].resource.body.properties.encryption.requireInfrastructureEncryption), "unknown")}."
  }

  # decision: storage-account__uploads.security.key_management
  assert {
    condition     = module.data.storage["uploads"].resource.body.properties.encryption.keySource == "Microsoft.Storage"
    error_message = "storage-account__uploads.security.key_management must be \"Microsoft.Storage\", got ${try(jsonencode(module.data.storage["uploads"].resource.body.properties.encryption.keySource), "unknown")}."
  }

  # decision: storage-account__uploads.security.sftp_enabled
  assert {
    condition     = module.data.storage["uploads"].resource.body.properties.isSftpEnabled == false
    error_message = "storage-account__uploads.security.sftp_enabled must be false, got ${try(jsonencode(module.data.storage["uploads"].resource.body.properties.isSftpEnabled), "unknown")}."
  }

  # decision: storage-account__host.security.shared_access_key_enabled
  assert {
    condition     = module.data.storage["host"].resource.body.properties.allowSharedKeyAccess == false
    error_message = "storage-account__host.security.shared_access_key_enabled must be false, got ${try(jsonencode(module.data.storage["host"].resource.body.properties.allowSharedKeyAccess), "unknown")}."
  }

  # decision: storage-account__host.security.min_tls_version
  assert {
    condition     = module.data.storage["host"].resource.body.properties.minimumTlsVersion == "TLS1_2"
    error_message = "storage-account__host.security.min_tls_version must be \"TLS1_2\", got ${try(jsonencode(module.data.storage["host"].resource.body.properties.minimumTlsVersion), "unknown")}."
  }

  # decision: storage-account__host.security.https_traffic_only
  assert {
    condition     = module.data.storage["host"].resource.body.properties.supportsHttpsTrafficOnly == true
    error_message = "storage-account__host.security.https_traffic_only must be true, got ${try(jsonencode(module.data.storage["host"].resource.body.properties.supportsHttpsTrafficOnly), "unknown")}."
  }

  # decision: storage-account__host.security.allow_blob_public_access
  assert {
    condition     = module.data.storage["host"].resource.body.properties.allowBlobPublicAccess == false
    error_message = "storage-account__host.security.allow_blob_public_access must be false, got ${try(jsonencode(module.data.storage["host"].resource.body.properties.allowBlobPublicAccess), "unknown")}."
  }

  # decision: storage-account__host.security.infrastructure_encryption_enabled
  assert {
    condition     = module.data.storage["host"].resource.body.properties.encryption.requireInfrastructureEncryption == true
    error_message = "storage-account__host.security.infrastructure_encryption_enabled must be true, got ${try(jsonencode(module.data.storage["host"].resource.body.properties.encryption.requireInfrastructureEncryption), "unknown")}."
  }

  # decision: storage-account__host.security.key_management
  assert {
    condition     = module.data.storage["host"].resource.body.properties.encryption.keySource == "Microsoft.Storage"
    error_message = "storage-account__host.security.key_management must be \"Microsoft.Storage\", got ${try(jsonencode(module.data.storage["host"].resource.body.properties.encryption.keySource), "unknown")}."
  }

  # decision: storage-account__host.security.sftp_enabled
  assert {
    condition     = module.data.storage["host"].resource.body.properties.isSftpEnabled == false
    error_message = "storage-account__host.security.sftp_enabled must be false, got ${try(jsonencode(module.data.storage["host"].resource.body.properties.isSftpEnabled), "unknown")}."
  }

  # decision: cosmos-db.security.local_authentication_disabled
  assert {
    condition     = module.data.cosmos.local_authentication_disabled == true
    error_message = "cosmos-db.security.local_authentication_disabled must be true, got ${try(jsonencode(module.data.cosmos.local_authentication_disabled), "unknown")}."
  }

  # decision: cosmos-db.security.key_based_metadata_writes
  assert {
    condition     = module.data.cosmos.access_key_metadata_writes_enabled == false
    error_message = "cosmos-db.security.key_based_metadata_writes must be false, got ${try(jsonencode(module.data.cosmos.access_key_metadata_writes_enabled), "unknown")}."
  }

  # not-testable: cosmos-db.security.key_management - platform-managed keys: the module is given no key, nothing to observe

  # decision: foundry.security.local_authentication_disabled
  assert {
    condition     = tostring(module.ai.foundry.resource.local_authentication_enabled) == "false"
    error_message = "foundry.security.local_authentication_disabled must be \"false\", got ${try(jsonencode(tostring(module.ai.foundry.resource.local_authentication_enabled)), "unknown")}."
  }

  # not-testable: foundry.security.key_management - platform-managed keys: the module is given no key, nothing to observe

  # decision: search-service.security.local_authentication_disabled
  assert {
    condition     = tostring(module.ai.search.resource.local_authentication_enabled) == "false"
    error_message = "search-service.security.local_authentication_disabled must be \"false\", got ${try(jsonencode(tostring(module.ai.search.resource.local_authentication_enabled)), "unknown")}."
  }

  # not-testable: search-service.security.key_management - platform-managed keys: the module is given no key, nothing to observe

  # not-testable: container-registry.security.admin_enabled - the container-registry module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-registry.security.anonymous_pull_enabled - the container-registry module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-registry.security.key_management - platform-managed keys: the module is given no key, nothing to observe

  # decision: function-app.security.https_only
  assert {
    condition     = module.compute.function.resource.body.properties.httpsOnly == true
    error_message = "function-app.security.https_only must be true, got ${try(jsonencode(module.compute.function.resource.body.properties.httpsOnly), "unknown")}."
  }

  # decision: function-app.security.min_tls_version
  assert {
    condition     = module.compute.function.resource.body.properties.siteConfig.minTlsVersion == "1.2"
    error_message = "function-app.security.min_tls_version must be \"1.2\", got ${try(jsonencode(module.compute.function.resource.body.properties.siteConfig.minTlsVersion), "unknown")}."
  }

  # not-testable: function-app.security.basic_auth_enabled - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: function-app.security.application_insights - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # decision: app-service__web.security.https_only
  assert {
    condition     = module.compute.app["web"].resource.body.properties.httpsOnly == true
    error_message = "app-service__web.security.https_only must be true, got ${try(jsonencode(module.compute.app["web"].resource.body.properties.httpsOnly), "unknown")}."
  }

  # decision: app-service__web.security.min_tls_version
  assert {
    condition     = module.compute.app["web"].resource.body.properties.siteConfig.minTlsVersion == "1.2"
    error_message = "app-service__web.security.min_tls_version must be \"1.2\", got ${try(jsonencode(module.compute.app["web"].resource.body.properties.siteConfig.minTlsVersion), "unknown")}."
  }

  # not-testable: app-service__web.security.ftps_state - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: app-service__web.security.basic_auth_enabled - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # decision: app-service__mcp.security.https_only
  assert {
    condition     = module.compute.app["mcp"].resource.body.properties.httpsOnly == true
    error_message = "app-service__mcp.security.https_only must be true, got ${try(jsonencode(module.compute.app["mcp"].resource.body.properties.httpsOnly), "unknown")}."
  }

  # decision: app-service__mcp.security.min_tls_version
  assert {
    condition     = module.compute.app["mcp"].resource.body.properties.siteConfig.minTlsVersion == "1.2"
    error_message = "app-service__mcp.security.min_tls_version must be \"1.2\", got ${try(jsonencode(module.compute.app["mcp"].resource.body.properties.siteConfig.minTlsVersion), "unknown")}."
  }

  # not-testable: app-service__mcp.security.ftps_state - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: app-service__mcp.security.basic_auth_enabled - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: key-vault.vault.sku - the key-vault module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: key-vault.vault.purge_protection - the key-vault module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: key-vault.vault.soft_delete_retention_days - the key-vault module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: key-vault.vault.rbac_authorization - the key-vault module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: key-vault.keys.key_management - platform-managed keys: the module is given no key, nothing to observe

}
