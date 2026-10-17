# Rendering a Log Analytics workspace as Terraform

Mapping from the question set to `azurerm_log_analytics_workspace`. General layout,
variables and tagging are in
[../../../../core/iac-rendering/references/terraform-idiom.md](../../../../core/iac-rendering/references/terraform-idiom.md).

## Decision → argument

| Decision | Argument |
|---|---|
| `retention_days` | `retention_in_days` (30–730; 30 is the floor on PerGB2018) |
| `daily_quota_gb` | `daily_quota_gb` — `-1` for no cap |
| `sku` | `sku` — `PerGB2018`, or `CapacityReservation` with `reservation_capacity_in_gb_per_day` |
| `public_network_access: disabled` | `internet_ingestion_enabled = false` **and** `internet_query_enabled = false` |
| `local_auth: disabled` | `local_authentication_disabled = true` |
| `rbac_only_access` | `allow_resource_only_permissions = false` — note the inversion |
| `immediate_purge_protection` | provider-side `permanently_delete_on_destroy` in the `features` block, inverted |

## The workspace

```hcl
resource "azurerm_log_analytics_workspace" "this" {
  name                = data.naming_name.log_analytics_workspace.name
  resource_group_name = var.resource_group_name
  location            = var.location

  sku               = "PerGB2018"
  retention_in_days = 30
  daily_quota_gb    = -1

  # Both, or logs arrive and nobody can read them.
  internet_ingestion_enabled = false
  internet_query_enabled     = false

  # Access is via Entra ID; the workspace key is a non-expiring bearer credential.
  local_authentication_disabled = true

  # false means RBAC on the workspace governs reads, rather than permissions
  # inherited from whichever resource emitted the row.
  allow_resource_only_permissions = false

  tags = local.tags
}
```

`allow_resource_only_permissions` is the inverse of the question — it is worth the comment
every time, because reading the argument name as the decision gets it backwards.

## Referencing one instead

`observability_ownership: reference` renders a data source, and the module takes the id as
a variable rather than looking it up repeatedly:

```hcl
data "azurerm_log_analytics_workspace" "platform" {
  name                = var.workspace_name
  resource_group_name = var.workspace_resource_group_name
}
```

## Soft delete and destroy

```hcl
provider "azurerm" {
  features {
    log_analytics_workspace {
      permanently_delete_on_destroy = false
    }
  }
}
```

`false` keeps Azure's 14-day soft delete. That is the right posture and it makes
`destroy` + `apply` with the same name inside the window either fail or recover the old
workspace with its old data — so a test harness that cycles workspaces wants a unique
name per run rather than `true` here.

## Tests

```hcl
run "workspace_is_not_publicly_queryable" {
  command = plan

  assert {
    condition = (
      azurerm_log_analytics_workspace.this.internet_ingestion_enabled == false &&
      azurerm_log_analytics_workspace.this.internet_query_enabled == false
    )
    error_message = "Both switches, or the workspace is half-private."
  }
}
```
