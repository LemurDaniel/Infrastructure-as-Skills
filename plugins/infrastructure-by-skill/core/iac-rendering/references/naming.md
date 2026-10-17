# Rendering names

Never hardcode a resource name. The two targets get there differently:

| Target | How a name is produced |
|---|---|
| Terraform | The `LemurDaniel/naming` provider resolves the CAF convention |
| Bicep | **Assembled from `var`s in the template.** The Bicep naming modules are not shipped yet |

Same convention and same abbreviations either way — on the Bicep side the author renders
them instead of a function.

## The resource identifier

The Terraform provider takes `<Provider>::<Namespace>/<Type>[::<kind>]`, e.g.
`Azure::Microsoft.Storage/storageAccounts`. The optional `kind` suffix selects a variant of
the same type — `Microsoft.Compute/disks::os` abbreviates to `osdisk`, `::data` to `disk`.

Each resource's `questions/<resource>.yaml` states that identifier under `naming:`, alongside
the plain Bicep resource type and the **abbreviation** the Bicep vars render. Use those
rather than constructing either yourself.

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

There is a naming engine in
[`LemurDaniel/BICEP__Registry`](https://github.com/LemurDaniel/BICEP__Registry/tree/master/modules/utility/naming)
under `modules/utility/naming/` (`schema` + `generator`, exporting `genName` /
`genNameId`). **Do not generate code against
it.** It is not ready to ship, and a template importing it is a template that breaks when
its interface moves. Never import `utility/naming/*`, never call `genName` or `genNameId`.

Assemble the name from `var`s instead, in the template, from the same parts the convention
uses:

```bicep
@allowed(['development', 'test', 'acceptance', 'production'])
param environment string
param location string = resourceGroup().location

@description('Workload short name, rendered into the resource name.')
param workload string

@description('Instance number, for a second account beside the first.')
param index int = 1

// CAF convention, assembled here until the naming modules ship.
var environmentAbbreviations = {
  development: 'dev'
  test: 'tst'
  acceptance: 'acc'
  production: 'prd'
}
var locationAbbreviations = {
  westeurope: 'we'
  northeurope: 'ne'
  germanywestcentral: 'gwc'
}

var affix = '${locationAbbreviations[location]}${environmentAbbreviations[environment]}'

// st + we + dev + objects + 01  ->  stwedevobjects01
var storageAccountName = toLower('st${affix}${workload}${padLeft(index, 2, '0')}')
```

### The parts

| Part | Source |
|---|---|
| Abbreviation (`st`, `vnet`, `kv`, …) | `naming.abbreviation` in the resource's question set — never guessed |
| Location short code | A `var` map in the template, keyed by the region the deployment uses |
| Environment short code | A `var` map, from the `environment` parameter |
| Workload | A parameter |
| Index | `padLeft(index, 2, '0')`, so `01` rather than `1` |

Declare the two maps once per deployment — in `main.bicep`, or in a shared `naming.bicep`
with `@export()`ed vars if more than two modules need them — and pass the rendered name
down as a parameter rather than repeating the maps per module.

### The rules the engine used to enforce

Assembling by hand means the per-type character rules are now the author's problem. State
them where they bite:

- **Storage accounts, container registries**: lowercase alphanumeric only, no separators,
  3–24 characters. `toLower()` and no `-`.
- **Key vaults**: 3–24 characters, hyphens allowed, must start with a letter.
- **Most others**: hyphens are conventional (`vnet-we-dev-myapp-01`).

Every resource's `references/<resource>/bicep.md` states its own limit. If a workload name
can push the rendered name past the limit, say so rather than letting the deployment fail
at creation.

### When the engine ships

This is a swap of the `var` block for two imports, with the identifier form changing (the
Bicep function takes the resource type *without* the `Azure::` prefix the Terraform
provider needs). Keeping the assembly in one `var` block per deployment — not inlined into
each resource's `name:` — is what makes that swap a small change.
