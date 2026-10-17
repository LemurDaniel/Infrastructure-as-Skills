# Rendering a storage account as Terraform

Mapping from the question set to `azurerm`. General file layout, variable and tagging
conventions are in
[../../../core/iac-rendering/references/terraform-idiom.md](../../../core/iac-rendering/references/terraform-idiom.md).

Verify argument names against the installed provider rather than this file where they
disagree — `azurerm` renames arguments across major versions, and the examples below are
written for 5.x (verified against 5.10):

```bash
terraform providers schema -json \
  | jq '.provider_schemas["registry.terraform.io/hashicorp/azurerm"].resource_schemas.azurerm_storage_account.block.attributes | keys'
```

## Decision → argument

| Decision | Argument |
|---|---|
| `public_network_access: disabled` | `public_network_access = "Disabled"` |
| `public_network_access: enabled_with_firewall` | `public_network_access = "Enabled"` + `network_rules.default_action = "Deny"` |
| `public_network_access: enabled` | `public_network_access = "Enabled"` + `network_rules.default_action = "Allow"` |
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

`public_network_access` is a string in 5.x. The 4.x bool `public_network_access_enabled`
still exists and is **deprecated** — the schema marks it, `validate` does not warn. A
repository already on 4.x keeps the bool; do not mix the two on one account.

With `shared_access_key_enabled = false` the **provider** also needs
`storage_use_azuread = true` in its `provider "azurerm"` block, or its own data-plane
reads (blob properties, containers) fail with a 403 after a successful create.

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
  public_network_access           = "Disabled"

  # Access is via Entra ID and RBAC. A key would bypass both and is not
  # attributable in the audit log.
  shared_access_key_enabled = false
  sftp_enabled              = false

  # Settable only at creation — changing it later replaces the account.
  infrastructure_encryption_enabled = true

  identity {
    type = "SystemAssigned"
  }

  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = false

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

  # Only with deployment.private_dns_records: deployment. Under `policy` - the
  # landing-zone default - a DeployIfNotExists policy writes the record, and a
  # zone group here would be a second writer: drift on every plan.
  dynamic "private_dns_zone_group" {
    for_each = var.private_dns_records == "deployment" ? [1] : []
    content {
      name                 = "default"
      private_dns_zone_ids = [var.private_dns_zone_ids[each.key]]
    }
  }

  # Under `policy`: the zone group the policy attaches would otherwise show up
  # as a change Terraform wants to remove on every plan.
  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }

  tags = local.tags
}
```

When the spec fixes `private_dns_records` (it always does — it is a deployment decision,
not a variable), render only the branch that applies: under `policy` no `dynamic` block and
no `private_dns_zone_ids` variable, just the `lifecycle` block with its comment. A
variable the caller can never meaningfully set is a question the interview already
answered.

`subnet_id` comes from `data.azurerm_subnet.private_endpoints.id` when the network is
referenced (`network_ownership: reference`), and from the deployment's own
`azurerm_subnet` resource when it is created — never from a hardcoded id.

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

Two settings, because the account and its blob service are two diagnostic targets. The
account itself emits **no log categories** — a setting on the account with an
`enabled_log` block is rejected at apply. `diagnostic_categories` therefore renders on the
blob service; the account gets metrics only:

```hcl
resource "azurerm_monitor_diagnostic_setting" "storage" {
  name                       = "diag"
  target_resource_id         = azurerm_storage_account.this.id
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.platform.id

  enabled_metric {
    category = "AllMetrics"
  }
}

# Blob data-plane logs attach to <account>/blobServices/default. A setting on
# the account alone collects no StorageRead/Write/Delete while looking configured.
resource "azurerm_monitor_diagnostic_setting" "storage_blob" {
  name                       = "diag"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.platform.id

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

One more pair per sub-resource that has an endpoint and is used (`fileServices`,
`queueServices`, `tableServices`) — a service nobody writes to needs no log.

The workspace id is read from the referenced workspace's data source
(`observability_ownership: reference`) or from the deployment's own
`azurerm_log_analytics_workspace` resource — not passed in as a bare id variable, which
would pin a subscription into the configuration.

## Tests

Assert the decisions, not the attributes. The platform data sources are mocked so the
plan needs no credentials — how, and why the mocked ids must parse, is in
[terraform-idiom.md](../../../core/iac-rendering/references/terraform-idiom.md#tests):

```hcl
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
}

run "name_follows_the_convention" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.name == "stweprodinvoicing01"
    error_message = "The name must come from naming.yaml, not from a literal."
  }
}

run "no_dns_zone_group_under_policy" {
  command = plan

  assert {
    condition     = length(azurerm_private_endpoint.storage["blob"].private_dns_zone_group) == 0
    error_message = "private_dns_records: policy - the platform writes the record, not this code."
  }
}
```

The naming provider is **not** mocked, so the second run asserts the name exactly as it
will be deployed — which is also the test that catches an edited `naming.yaml`.
