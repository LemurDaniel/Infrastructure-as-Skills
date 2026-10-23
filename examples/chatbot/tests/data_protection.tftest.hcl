# data_protection: plan-only, platform mocked, naming provider real. Mocks and variables repeat in every
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

run "data_protection" {
  command = plan

  # decision: log-analytics-workspace.cost.retention_days
  assert {
    condition     = module.workspace.resource.retention_in_days == 30
    error_message = "log-analytics-workspace.cost.retention_days must be 30, got ${try(jsonencode(module.workspace.resource.retention_in_days), "unknown")}."
  }

  # decision: log-analytics-workspace.cost.daily_quota_gb
  assert {
    condition     = module.workspace.resource.daily_quota_gb == -1
    error_message = "log-analytics-workspace.cost.daily_quota_gb must be -1, got ${try(jsonencode(module.workspace.resource.daily_quota_gb), "unknown")}."
  }

  # decision: log-analytics-workspace.cost.sku
  assert {
    condition     = module.workspace.resource.sku == "PerGB2018"
    error_message = "log-analytics-workspace.cost.sku must be \"PerGB2018\", got ${try(jsonencode(module.workspace.resource.sku), "unknown")}."
  }

  # not-testable: log-analytics-workspace.data_protection.immediate_purge_protection - the module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: log-analytics-workspace.data_protection.archive_to_storage - the module exposes no attribute for it; set through the module input, reviewed in the call

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

  # not-testable: foundry.models.model_deployments - model deployments are child resources of the module, which the root cannot read

  # not-testable: foundry.models.deployment_sku - model deployments are child resources of the module, which the root cannot read

  # not-testable: foundry.models.deployment_capacity - model deployments are child resources of the module, which the root cannot read

  # not-testable: foundry.models.version_upgrade_option - model deployments are child resources of the module, which the root cannot read

  # not-testable: foundry.models.content_filter - model deployments are child resources of the module, which the root cannot read

  # not-testable: function-app.storage.host_storage_account - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: function-app.storage.host_storage_auth - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: function-app.storage.deployment_container - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

}
