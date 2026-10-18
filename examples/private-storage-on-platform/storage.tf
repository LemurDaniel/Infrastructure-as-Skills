# Rendered from ../infra-spec.yaml: deployment.module_source: avm, so the account is
# one call to Azure/avm-res-storage-storageaccount, every decision an explicit input.
# Version resolved 2026-10-18 from the module repository's tags: v0.10.0.

data "naming_name" "storage_account" {
  resource = "Azure::Microsoft.Storage/storageAccounts"
}

# One name per sub-resource: the convention's <?SUBNAME;-%s> token carries the
# sub-resource, so the index stays last - pep-we-prod-invoicing-blob-01.
data "naming_name" "private_endpoint" {
  for_each = toset(var.private_endpoint_subresources)

  resource   = "Azure::Microsoft.Network/privateEndpoints"
  parameters = { subname = each.key }
}

module "storage" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "~> 0.10.0"

  name      = data.naming_name.storage_account.name
  location  = var.location
  parent_id = data.azurerm_resource_group.this.id

  account_kind = "StorageV2"
  # decision: storage-account.data_protection.replication - the SKU name carries it;
  # account_tier / account_replication_type are ignored while this is set.
  account_sku_name = "Standard_ZRS"
  # decision: storage-account.data_protection.access_tier
  access_tier = "Hot"

  # decision: storage-account.networking.public_network_access - a bool on the module,
  # rendered as publicNetworkAccess: Disabled in the body.
  public_network_access_enabled = false
  # Present although public access is off: documents the posture, and the bypass is a
  # recorded decision (storage-account.networking.allow_azure_services_bypass).
  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  # Explicit although several match the module default: a reviewer reads the call,
  # not the module, and a module minor can move a default.
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  # Access is via Entra ID and RBAC; the module itself never uses a key.
  shared_access_key_enabled = false
  sftp_enabled              = false
  # Settable only at creation. The module default is false.
  infrastructure_encryption_enabled = true

  managed_identities = {
    system_assigned = true
  }

  # Soft delete, versioning and the change feed live on the blob service; the module
  # renders them as its blob_service child.
  blob_properties = {
    versioning_enabled = true
    change_feed        = { enabled = false }
    delete_retention_policy = {
      enabled = true
      days    = 7
    }
    container_delete_retention_policy = {
      enabled = true
      days    = 7
    }
  }

  # One endpoint per sub-resource, into the platform's private-endpoint subnet.
  private_endpoints = {
    for sub in var.private_endpoint_subresources : sub => {
      name               = data.naming_name.private_endpoint[sub].name
      subnet_resource_id = data.azurerm_subnet.private_endpoints.id
      subresource_name   = sub
    }
  }
  # deployment.private_dns_records: policy - the landing zone's DeployIfNotExists policy
  # attaches the privatelink zone and writes the record. false means the module renders
  # no zone group, so there is no second writer.
  private_endpoints_manage_dns_zone_group = false

  # Two targets: the account emits metrics only, the blob service carries the logs.
  diagnostic_settings_storage_account = {
    platform = {
      name                  = "diag"
      workspace_resource_id = data.azurerm_log_analytics_workspace.platform.id
      metrics               = [{ category = "AllMetrics" }]
    }
  }
  diagnostic_settings_blob = {
    platform = {
      name                  = "diag"
      workspace_resource_id = data.azurerm_log_analytics_workspace.platform.id
      logs                  = [{ category_group = "audit" }]
      metrics               = [{ category = "AllMetrics" }]
    }
  }

  # Data-plane roles on the account, by name. Empty until the consumer is named (spec: open).
  role_assignments = {
    for ra in var.role_assignments : "${ra.principal_id}-${ra.role}" => {
      role_definition_id_or_name = ra.role
      principal_id               = ra.principal_id
    }
  }

  enable_telemetry = true # deployment.module_telemetry: enabled
  tags             = local.tags
}
