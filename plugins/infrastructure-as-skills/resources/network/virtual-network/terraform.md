# Rendering a virtual network as Terraform

Mapping from the question set to `azurerm_virtual_network` and `azurerm_subnet`. General
layout, variables and tagging are in
[../../../core/iac-rendering/references/terraform-idiom.md](../../../core/iac-rendering/references/terraform-idiom.md).

## Decision → argument

| Decision | Argument |
|---|---|
| `address_space` | `azurerm_virtual_network.address_space` (a list, even with one entry) |
| `dns_servers` | `azurerm_virtual_network.dns_servers` — omit for Azure DNS |
| `ddos_protection` | `ddos_protection_plan { id, enable }` block |
| `subnets` | One `azurerm_subnet` each — **not** a `subnet` block on the vnet |
| `private_endpoint_network_policies` | `azurerm_subnet.private_endpoint_network_policies` (string, not bool) |
| `service_endpoints` | `azurerm_subnet.service_endpoints` |
| `subnet_delegations` | `delegation { name, service_delegation { name, actions } }` |

## The network and its subnets

```hcl
resource "azurerm_virtual_network" "this" {
  name                = data.naming_name.virtual_network.name
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.address_space]

  tags = local.tags
}

resource "azurerm_subnet" "this" {
  for_each = var.subnets

  name                 = each.key
  resource_group_name  = azurerm_virtual_network.this.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.prefix]

  # Enabled, so the subnet's NSG and routes apply to private endpoint traffic.
  private_endpoint_network_policies = "Enabled"

  service_endpoints = lookup(each.value, "service_endpoints", [])
}
```

`for_each` over a map keyed by subnet name, never `count`. With `count`, removing the
second of three subnets renumbers the third and Terraform plans a destroy and recreate of
a subnet that did not change — and a subnet recreate takes its private endpoints with it.

Never set a `subnet` block on `azurerm_virtual_network` while also declaring
`azurerm_subnet` resources. Both own the same API field, so each apply undoes the other.

## Delegation

```hcl
  dynamic "delegation" {
    for_each = lookup(each.value, "delegation", null) == null ? [] : [each.value.delegation]

    content {
      name = "delegation"
      service_delegation {
        name = delegation.value   # e.g. "Microsoft.Web/serverFarms"
      }
    }
  }
```

Leave `actions` unset unless something needs a non-default set — the provider fills the
service's required actions, and a hand-written list that disagrees with the service is
rejected at apply with a message that does not name the mismatch.

## Outputs

```hcl
output "id" { value = azurerm_virtual_network.this.id }
output "name" { value = azurerm_virtual_network.this.name }

output "subnet_ids" {
  value = { for k, s in azurerm_subnet.this : k => s.id }
}
```

A map keyed by subnet name, so a consumer writes `module.network.subnet_ids["endpoints"]`
rather than indexing a list whose order is incidental.

## Tests

```hcl
run "endpoint_subnet_is_large_enough" {
  command = plan

  variables {
    address_space = "10.42.0.0/16"
    subnets       = { endpoints = { prefix = "10.42.1.0/27" } }
  }

  assert {
    condition     = cidrnetmask(azurerm_subnet.this["endpoints"].address_prefixes[0]) != "255.255.255.248"
    error_message = "A /29 leaves three usable addresses after Azure's five reserved."
  }
}
```
