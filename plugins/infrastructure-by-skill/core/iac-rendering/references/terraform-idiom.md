# Rendering Terraform

How generated HCL should look. Match the surrounding repository first — if it already has a
layout, follow that and ignore the defaults below.

## File layout

One concern per file, named after it. Not `main.tf` holding everything:

```
storage.tf              # the resource and what belongs only to it
storage.network.tf      # private endpoint, DNS record, firewall rules
variables.tf
outputs.tf
providers.tf            # required_providers + the naming provider block
locals.tf               # tags, derived values
infra-spec.yaml
tests/
  storage.tftest.hcl
```

The reason to split is review, not tidiness: a private endpoint change and a retention
change land in different files and can be read apart.

That is the `granularity: single` shape. With modules, the same files move one level down.

## Modules

The split comes from the spec's `composition` block, not from taste — see
[spec.md](../../iac-authoring/references/spec.md). One `composition.modules` entry is one
directory:

```
main.tf                 # the root: module calls and the wiring between them
variables.tf
outputs.tf
providers.tf
modules/
  storage/
    main.tf             # the resource and what belongs only to it
    network.tf          # private endpoint, DNS record
    variables.tf        # exactly the entry's inputs
    outputs.tf          # exactly the entry's outputs
```

The root is a composition, not a place to sneak in one more resource. If something does not
fit in a module it is wiring, and wiring is the root's job — role assignments, DNS records
and diagnostic routing between two modules go there because only the root can see both.

```hcl
module "storage" {
  source = "./modules/storage"

  environment         = var.environment
  location            = var.location
  workload            = var.workload
  resource_group_name = var.resource_group_name
}

module "storage_network" {
  source = "./modules/storage-network"

  # The spec's needs: [storage] — an output, never a reach into its resources.
  storage_account_id = module.storage.id
  subnet_id          = var.subnet_id
}
```

### What does not port to Bicep unchanged

- **A provider is configured in the root, never in a module.** A module deploying into a
  different subscription takes a provider alias through `providers = { azurerm = azurerm.other }`.
  Bicep does the same thing with a per-module `scope:`, which is a module property there
  and a provider plumbing problem here.
- **`depends_on` on a module is rarely needed.** Passing an output already creates the
  edge. Reach for it only for a dependency Terraform cannot see, and say why in a comment.
- **`for_each` over a module** is the idiom for n instances. Keep the key meaningful
  (`for_each = toset(["blob", "file"])`) — the key lands in the resource address, and an
  index-keyed one renumbers everything when the list changes.

### Reusing a published module

A spec module with `implementation: reuse` renders as a call to a registry module instead
of resources of its own. Which module that is, is resolved here — the spec carries no
coordinate, on purpose.

```hcl
module "storage" {
  source  = "Azure/storage/azurerm"
  version = "~> 0.5"
  # ...
}
```

Pin `version` always. `source` without `version` re-resolves on every `init` and turns a
module release into an unannounced change. A local path (`./modules/storage`) takes no
`version` and is the other half of the same rule: those two forms, nothing in between.

### Do not generate a module per resource by reflex

`granularity: per-resource` exists for patterns whose parts get reused separately. A
one-resource module whose variables restate the resource's arguments is a wrapper that adds
a file to read and removes nothing from the one below it.

## Resource naming inside HCL

Use `this` for the single resource a file is about — `azurerm_storage_account.this`, not
`azurerm_storage_account.storage_account`. The type already says what it is, so repeating
it in the label adds length without information. Where several of a type coexist, name them
by role: `.data`, `.logs`, `.state`.

Names of the Azure resources themselves always come from the naming provider. See
[naming.md](naming.md); never `format()` a name together.

## Referencing a network the deployment does not own

`network_ownership: reference` in the spec means the virtual network is read, never managed.
That is a `data` block, and the distinction matters: a `resource` block pointed at
someone else's network will try to converge it to what the configuration says.

```hcl
data "azurerm_virtual_network" "platform" {
  name                = var.vnet_name
  resource_group_name = var.network_resource_group_name
}

data "azurerm_subnet" "private_endpoints" {
  name                 = var.private_endpoint_subnet_name
  virtual_network_name = data.azurerm_virtual_network.platform.name
  resource_group_name  = data.azurerm_virtual_network.platform.resource_group_name
}
```

By name and resource group, not by a hardcoded id — an id pins a subscription into the
configuration and makes the same code undeployable in the next one.

With `create`, the same subnet is a resource the deployment owns and the private endpoints
reference it directly. Never both: a configuration that creates a network and also reads a
foreign one has two sources of truth for its address space, and the overlap surfaces at the
first peering.

## Variables

Every variable carries a `description` and an explicit `type`. A variable without a
description is a question the question set should have asked.

```hcl
variable "environment" {
  description = "Deployment environment. Drives the rendered name, the tags and several security defaults."
  type        = string

  validation {
    condition     = contains(["development", "test", "acceptance", "production"], var.environment)
    error_message = "environment must be one of development, test, acceptance, production."
  }
}
```

Validate what the question set constrained. An `enum` question with four `values` becomes a
`contains()` validation — otherwise the constraint existed only during the interview and
the code accepts anything.

Prefer `optional()` in object types over separate variables with defaults. It keeps a
resource's inputs in one shape instead of scattering them across the file.

## Tags

Tags come from a local, merged once, applied everywhere. Never hand-written per resource —
a resource with its own tag literal drifts from its siblings the first time the set
changes.

```hcl
locals {
  # The set itself comes from the repository or the spec's context.tags,
  # not from this file. Match whatever the surrounding code already applies.
  tags = merge(var.tags, local.derived_tags)
}

resource "azurerm_storage_account" "this" {
  tags = local.tags
  # ...
}
```

Which tags those are is not a rendering decision — see
[guardrails.md](../../iac-authoring/references/guardrails.md). If the repository has a tag
local already, use it rather than adding a second one beside it.

## Secure defaults are explicit

Write the secure value even where it is already the provider default. The provider default
can change between major versions, and more importantly an explicit `false` is reviewable
while an absent argument is invisible:

```hcl
resource "azurerm_storage_account" "this" {
  name                = data.naming_name.storage_account.name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_tier             = "Standard"
  account_replication_type = "ZRS"

  # Explicit, though several match the provider default: a reviewer can see
  # a decision that was made, and a provider major version cannot move it.
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = false
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  infrastructure_encryption_enabled = true

  tags = local.tags
}
```

Comment the ones whose reason is not obvious from the name, and keep that comment to the
*why* — the `how` is the line above it.

## Tests

Generate a `.tftest.hcl` alongside, asserting the decisions the question set recorded.
Plan-only (`command = plan`) so it needs no credentials:

```hcl
run "storage_account_is_private" {
  command = plan

  variables {
    environment = "production"
    location    = "westeurope"
    workload    = "myapp"
  }

  assert {
    condition     = azurerm_storage_account.this.public_network_access_enabled == false
    error_message = "The storage account must not be reachable from the public internet."
  }

  assert {
    condition     = azurerm_storage_account.this.shared_access_key_enabled == false
    error_message = "Shared key auth must stay off; access is via Entra ID and RBAC."
  }
}
```

Assert the *decisions*, not every attribute. A test that restates the whole resource fails
on every edit and teaches nobody anything; a test named after a decision fails exactly when
that decision is reversed.

One trap worth knowing from the naming module's own suite: in `.tftest.hcl`, a value coming
back as a **tuple** does not compare equal to a list literal. Index into it or compare
element-wise.

## Before handing over

```bash
terraform fmt -recursive
terraform validate
terraform test        # if tests were generated
```

`fmt` is not optional — unformatted generated code is the fastest way to make a reviewer
distrust the rest of it.

Then the step that tells you what would actually change:

```bash
terraform plan -out=tfplan
```

Do not report "plan succeeded" as the result. A plan that succeeds and replaces the
production database has succeeded. Read it out: what is created, changed and destroyed;
every `-/+` replacement named with the attribute that forces it; which of the rest a
consumer would notice; and what the plan cannot see — data not migrated, a role assignment
that takes minutes to propagate, a consumer still holding a connection string.
