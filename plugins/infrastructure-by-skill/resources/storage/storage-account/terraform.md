# Rendering a storage account as Terraform

Mapping from the question set to `azurerm`. General file layout, variable and tagging
conventions are in
[../../../../core/iac-rendering/references/terraform-idiom.md](../../../../core/iac-rendering/references/terraform-idiom.md).

Verify argument names against the installed provider rather than this file where they
disagree — `azurerm` renames arguments across major versions, and the examples below are
written for 4.x:

```bash
terraform providers schema -json \
  | jq '.provider_schemas["registry.terraform.io/hashicorp/azurerm"].resource_schemas.azurerm_storage_account.block.attributes | keys'
```

## Decision → argument

| Decision | Argument |
|---|---|
| `public_network_access: disabled` | `public_network_access_enabled = false` |
| `public_network_access: enabled_with_firewall` | `public_network_access_enabled = true` + `network_rules.default_action = "Deny"` |
| `public_network_access: enabled` | `public_network_access_enabled = true` + `network_rules.default_action = "Allow"` |
| `shared_access_key_enabled` | `shared_access_key_enabled` |
| `https_traffic_only` | `https_traffic_only_enabled` (was `enable_https_traffic_only` before 4.0) |
| `allow_blob_public_access` | `allow_nested_items_to_be_public` |
| `replication` | `account_replication_type` |
| `access_tier` | `access_tier` |
| `blob_soft_delete_days` | `blob_properties.delete_retention_policy.days` |
| `container_soft_delete_days` | `blob_properties.container_delete_retention_policy.days` |
| `versioning_enabled` | `blob_properties.versioning_enabled` |
| `change_feed_enabled` | `blob_properties.change_feed_enabled` |
| `point_in_time_restore_days` | `blob_properties.restore_policy.days` |
| `sftp_enabled` | `sftp_enabled` (requires `is_hns_enabled = true`) |

`account_tier` is not a question — it follows from `replication` and `access_tier`. Standard
unless the answers call for premium block blob.

## The account

```hcl
data "naming_name" "storage_account" {
  resource = "Azure::Microsoft.Storage/storageAccounts"
}

resource "azurerm_storage_account" "this" {
  name                = data.naming_name.storage_account.name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_tier             = "Standard"
  account_kind             = "StorageV2"
  account_replication_type = "ZRS"
  access_tier              = "Hot"

  # Explicit although several match the provider default: a reviewer can see a
  # decision that was made, and a provider major version cannot move it.
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false

  # Access is via Entra ID and RBAC. A key would bypass both and is not
  # attributable in the audit log.
  shared_access_key_enabled = false

  # Settable only at creation — changing it later replaces the account.
  infrastructure_encryption_enabled = true

  identity {
    type = "SystemAssigned"
  }

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.tags
}
```

### The `network_rules` trap

`network_rules` is a nested block on the account *and* also available as the standalone
`azurerm_storage_account_network_rules` resource. Using both for one account produces a
permanent diff, each fighting the other on every plan. Pick the nested block for a new
account; the standalone resource exists for breaking a dependency cycle where a subnet
rule must be added after something the account itself is needed for.

Render it only when `public_network_access` is not `disabled` — with public access off the
ACL has nothing to filter:

```hcl
dynamic "network_rules" {
  for_each = var.public_network_access == "disabled" ? [] : [1]

  content {
    default_action             = var.public_network_access == "enabled" ? "Allow" : "Deny"
    bypass                     = var.allow_azure_services_bypass ? ["AzureServices"] : ["None"]
    ip_rules                   = var.firewall_ip_rules
    virtual_network_subnet_ids = var.firewall_subnet_rules
  }
}
```

`bypass` must be `["None"]` rather than `[]` when the bypass is off — an empty list is not
the same thing to the API.

## Private endpoint

One endpoint per sub-resource, in `storage.network.tf`. The DNS zone is referenced, never
created:

```hcl
data "naming_name" "private_endpoint" {
  resource = "Azure::Microsoft.Network/privateEndpoints"
}

resource "azurerm_private_endpoint" "storage" {
  for_each = toset(var.private_endpoint_subresources)

  name                = "${data.naming_name.private_endpoint.name}-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-${each.key}"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = [each.key]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_ids[each.key]]
  }

  tags = local.tags
}
```

`subresource_names` takes exactly one entry per endpoint. Passing several is accepted at
plan time and fails at apply.

## Role assignments

Scoped to the container where possible, never to the subscription:

```hcl
resource "azurerm_role_assignment" "data" {
  for_each = { for ra in var.role_assignments : "${ra.principal_id}-${ra.role}" => ra }

  scope                = coalesce(each.value.scope, azurerm_storage_account.this.id)
  role_definition_name = each.value.role
  principal_id         = each.value.principal_id
}
```

Use the data-plane roles — `Storage Blob Data Reader`, `Storage Blob Data Contributor`.
`Contributor` and `Owner` are control-plane roles and grant no data access at all, which is
a confusion worth catching in review: an application given `Contributor` on a storage
account still cannot read a blob.

## Customer-managed keys

Only when `key_management: customer_managed`. With a system-assigned identity the
dependency is circular — the identity does not exist until the account does — so either use
a user-assigned identity, or create the account with platform keys and apply
`azurerm_storage_account_customer_managed_key` afterwards:

```hcl
resource "azurerm_storage_account_customer_managed_key" "this" {
  storage_account_id        = azurerm_storage_account.this.id
  key_vault_key_id          = var.cmk_key_vault_key_id
  user_assigned_identity_id = var.user_assigned_identity_id
}
```

Prefer the user-assigned identity. It removes the cycle, and the wrap/unwrap grant can be
in place before the account exists.

## Diagnostics

```hcl
resource "azurerm_monitor_diagnostic_setting" "storage" {
  name                       = "diag"
  target_resource_id         = azurerm_storage_account.this.id
  log_analytics_workspace_id = var.diagnostic_workspace_id

  dynamic "enabled_log" {
    for_each = toset(var.diagnostic_categories)
    content {
      category_group = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
```

Blob data-plane logs attach to the blob service, not the account — the target id needs
`/blobServices/default` appended. A diagnostic setting on the account alone collects no
`StorageRead` or `StorageWrite` events, which is a silent gap that looks configured.

## Tests

Assert the decisions, not the attributes:

```hcl
run "account_is_private_and_keyless" {
  command = plan

  variables {
    environment           = "production"
    location              = "westeurope"
    resource_group_name   = "rg-test"
    diagnostic_workspace_id = "/subscriptions/0/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/law"
  }

  assert {
    condition     = azurerm_storage_account.this.public_network_access_enabled == false
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
}
```
