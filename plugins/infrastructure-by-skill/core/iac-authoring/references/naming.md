# Rendering names

Never hardcode a resource name and never assemble one with `format()` or string
interpolation. Both targets have a naming engine that resolves a CAF convention, and the
whole point of it is that the convention lives in one place.

## The resource identifier differs between the two targets

This is the single most common error when generating for both. Same convention, same
abbreviation tables, different identifier syntax:

| Target | Identifier | Example |
|---|---|---|
| Terraform (`naming` provider) | `<Provider>::<Namespace>/<Type>[::<kind>]` | `Azure::Microsoft.Storage/storageAccounts` |
| Bicep (`genName`) | `<Namespace>/<Type>[::<kind>]` | `Microsoft.Storage/storageAccounts` |

The Terraform provider carries a cloud-provider prefix; the Bicep function does not. The
optional `kind` suffix works identically in both and selects a variant of the same type —
`Microsoft.Compute/disks::os` abbreviates to `osdisk`, `::data` to `disk`.

Each resource skill's `questions.yaml` states both forms under `naming:`. Use those rather
than constructing the identifier yourself.

## Terraform

### Use the provider, not the modules

The [`LemurDaniel/naming`](https://registry.terraform.io/providers/LemurDaniel/naming/latest)
provider supersedes the two older modules (`LemurDaniel/naming-schema/random` and
`LemurDaniel/naming/random`) — same engine, ported and tested against the modules'
fixtures, without the `module` blocks and output plumbing in between. New code uses the
provider.

The modules remain correct and are not deprecated out from under anyone. Keep using them
in a repository that already does; mixing both in one configuration only invites the
question of which one rendered a given name.

```hcl
terraform {
  required_providers {
    naming = {
      source  = "LemurDaniel/naming"
      version = "~> 1.0"
    }
  }
}

# The convention is declared once, for the whole configuration.
provider "naming" {
  convention = "default"

  parameters = {
    location    = var.location
    environment = var.environment
    name        = var.workload
  }
}

data "naming_name" "storage_account" {
  resource = "Azure::Microsoft.Storage/storageAccounts"
}

resource "azurerm_storage_account" "this" {
  name = data.naming_name.storage_account.name # stwedevmyapp01
  # ...
}
```

### `naming_name` arguments

| Argument | Notes |
|---|---|
| `resource` | Required. `"Azure::<Namespace>/<Type>[::<kind>]"`. |
| `index` | `{ start, count }`. `count` is **how many names** to render, `start` only shifts the first index. |
| `naming_id` | Selects a named pattern/abbreviation variant. Takes precedence over `kind`. |
| `parameters` | Map of string, layered over the provider's `parameters`. |

Read-only: `name` (the first name), `at_index` (all of them, in index order), plus the
aliases `result` and `by_index`.

### The index trap

`index.count` is a quantity, not an upper bound, and the convention's `index_modifier`
shifts on top of `start`. With the bundled `index_modifier: 1`, `{ start = 2, count = 5 }`
renders five names numbered `03` through `07`. If you want three sequential vnets, that is
`count = 3` — not `start = 3`.

```hcl
data "naming_name" "virtual_networks" {
  resource = "Azure::Microsoft.Network/virtualNetworks"
  index    = { count = 3 }
}

resource "azurerm_virtual_network" "this" {
  count = 3
  name  = data.naming_name.virtual_networks.at_index[count.index]
  # ...
}
```

### Provider arguments

| Argument | Notes |
|---|---|
| `convention` | Bundled convention name. Defaults to `"default"` (CAF abbreviations). |
| `naming` | Path to a YAML file partially overriding the convention. Merged per key, so an override may set one abbreviation without restating the block. |
| `parameters` | `location`, `environment`, `name`, … that the patterns render from. |
| `random_seed` | Only needed if a pattern you use contains the `<UNIQUE_ID_n>` token. The same seed always resolves to the same id, so names stay stable with nothing in state. |

Everything resolves during `plan`: embedded YAML merged in memory, no API calls, nothing
persisted. That is why it is a data source rather than a resource — rendering is pure.

## Bicep

The naming engine ships as two modules in `BICEP__Module-Registry` under
`modules/utility/naming/`: `schema` resolves the convention, `generator` exports the
rendering functions.

```bicep
import { schema } from 'br/modules:utility/naming/schema:5.5.0'
import { genName, genNameId } from 'br/modules:utility/naming/generator:5.5.0'

param location string = resourceGroup().location
param environment string = 'development'

var storageAccountName = genName('Microsoft.Storage/storageAccounts', schema.default, location, {
  name: 'objects'
  environment: environment
})
```

The `br/modules:` alias resolves through `bicepconfig.json` to the registry ACR. Pin the
version — check `version.json` next to the module for what is current rather than assuming.

### The two functions

```bicep
genName(resourceType, schema, location, parameters)
genNameId(resourceType, id, schema, location, parameters)
```

`genNameId` supplies the explicit `id` that selects a pattern variant; it is the Bicep
equivalent of Terraform's `naming_id`. Resolution order inside the engine is worth knowing
when a name comes out unexpected: **patterns prefer `id` over `kind`**, while
**abbreviations prefer `kind` over `id`**, and both fall back to `default` and then to the
bare resource type.

`parameters` accepts `index` (an int, default `1`), `overwrite` (bypasses rendering
entirely — treat as an escape hatch that needs a comment saying why), and any string
parameters the pattern references.

### Local vs. registry imports

Inside `BICEP__Module-Registry` itself the modules import each other by relative path
(`'../../schema/module.bicep'`). Outside it, use the `br/modules:` registry reference.
Generating a relative path into a consumer repository produces a file that compiles on the
author's machine and nowhere else.
