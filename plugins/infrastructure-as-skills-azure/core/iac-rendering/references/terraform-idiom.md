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
environments/
  development.tfvars    # one file per stage in context.environments - the per-stage values
  test.tfvars
  production.tfvars
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

### Context values are always variables

`subscription_id`, `resource_group_name`, `location` and `workload` are root `variable`s
with no default, in every rendering. Never a literal in a `.tf` file, and never a value the
interview invented. The provider block reads `var.subscription_id`; `workload` carries a
`validation` for the length limit. Values the user stated go into a `*.tfvars.example`.

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

### Azure Verified Modules are the default module

A resource renders as a call to its AVM module unless the spec says `implementation:
authored` for it — which module, which version and how the shared interfaces map is in
[avm.md](avm.md). The call takes the rendered name, the context variables and every
decision as an explicit input:

```hcl
module "storage" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "~> 0.10.0" # resolved 2026-10-17; 0.y minors break, so the minor is fixed

  name      = data.naming_name.storage_account.name
  location  = var.location
  parent_id = data.azurerm_resource_group.this.id # AzAPI-based module: the group's id, not its name

  # decision: storage-account.networking.public_network_access
  public_network_access_enabled = false
  # ...every other decision, written even where it matches the module default

  enable_telemetry = true # deployment.module_telemetry
  tags             = local.tags
}
```

Pin `version` always, to the version resolved at render time. `source` without `version`
re-resolves on every `init` and turns a module release into an unannounced change. A
local path (`./modules/storage`) takes no `version` and is the other half of the same
rule: those two forms, nothing in between. `implementation: reuse` — a module the user
named that is not AVM — takes the same shape with the user's coordinate.

The module's provider requirements become the root's: an AzAPI-based module needs
`Azure/azapi`, `Azure/modtm` and `hashicorp/random` declared in `required_providers`
beside `azurerm` and `naming`, and an azurerm-based module may pin `azurerm` to a major
the root did not plan on. Read the module README's *Requirements* before writing
`providers.tf`; the details are in [avm.md](avm.md#provider-requirements-terraform).

With AVM the module split is mostly decided: one module call per resource, the
resource's own private endpoints, diagnostics and role assignments as its inputs, and the
root holding the wiring between modules. `composition.granularity: per-concern` describes
the authored layout; under AVM it collapses to `single` unless a pattern says otherwise.

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
    # The keys of mappings.environment in naming.yaml that this deployment uses -
    # an environment the convention cannot abbreviate cannot be named.
    condition     = contains(["development", "test", "staging", "production"], var.environment)
    error_message = "environment must be one of development, test, staging, production."
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
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  public_network_access             = "Disabled"
  shared_access_key_enabled         = false
  allow_nested_items_to_be_public   = false
  infrastructure_encryption_enabled = true

  tags = local.tags
}
```

Comment the ones whose reason is not obvious from the name, and keep that comment to the
*why* — the `how` is the line above it.

## The context values and the stage files

`context:` and the refs under `deployment:` are variables, and so is every decision whose
question is `per_environment` or whose spec value is a map keyed by stage. Their values go
into **one file per stage**, `environments/<stage>.tfvars` — the subscription, the resource
group, the referenced network and workspace by name, the address ranges, the cost knobs
(`replication`, `log_retention_days`) that `non_production_savings` sets cheaper outside
production. Not into variable `default`s: a default makes the value look optional, and the
next stage then inherits production's subscription by forgetting to set it. Not as
literals in the template: a literal range is the one that is wrong in every stage but
one. The files are committed; they hold names and ids, never a secret.

**A stage whose values are still `open:` in the spec gets its file anyway, with
placeholders** - the scaffold stands, and filling it in is an edit of values, not of
structure. The convention is the same for every target and every pipeline:

- an open id is the all-zero GUID `00000000-0000-0000-0000-000000000000`; an open name is
  `OPEN-<what>` (`OPEN-resource-group`, `OPEN-hub-vnet`). Nothing is invented that looks
  real;
- what the spec does know stays real - `environment`, `location`, `workload`, and the
  `non_production_default` knobs (`replication = "LRS"`);
- the file opens with a comment naming the spec's `open:` entries for that stage and who
  answers them;
- **a placeholder never deploys.** The pipeline's first step in a stage refuses a file that
  holds either marker ([pipelines.md](pipelines.md)), and the spec's `open:` entries keep
  blocking `apply`. Placeholders stand in for values nobody has given; they are not
  `assumed` values and not a default.

One state per stage, chosen at init by the backend key and never by a workspace — a
workspace is invisible in the file tree and the thing a pipeline forgets to select:

```bash
terraform init -backend-config="key=<workload>/<stage>.tfstate"
terraform plan -var-file=environments/<stage>.tfvars
```

The backend's values (its storage account and container) are the consuming repository's;
the render adds the key convention as a comment in `providers.tf` and never a backend
with values of its own. With a pipeline (`deployment.deploy_mechanism` other than
`local`) it adds the **empty** block `backend "azurerm" {}` as well, because the pipeline
passes the values as `-backend-config` and `terraform init` ignores `-backend-config`
without raising an error when no backend block exists - the state would be local, and gone
with the runner. A local run without a state uses `terraform init -backend=false`. The test file plans a non-production stage once besides the
decisions' runs: the name carries the stage's code, the savings knob lands where it
renders.

## Tests

Generate a `.tftest.hcl` alongside, asserting the decisions the question set recorded.
Plan-only (`command = plan`) so it needs no credentials.

**Coverage is the contract, not the example.** Every decision under `resources:` in the
spec gets exactly one `assert`, and the assert names it in a comment on the line above:

```hcl
  # decision: storage-account.security.min_tls_version
  assert {
    condition     = azurerm_storage_account.this.min_tls_version == "TLS1_2"
    error_message = "TLS 1.2 is the floor."
  }
```

`<resource>.<group>.<question>` — the key path in the spec. One `run` per question-set
group (`networking`, `security`, `data_protection`, `observability`, …) plus one for
naming, so a failure names the concern before the attribute. A decision whose consequence
a plan cannot observe — a firewall bypass that is only rendered when public access is on,
a provider `features` setting — is still named, with its reason, so the gap is a
sentence rather than a silence:

```hcl
# not-testable: storage-account.networking.allow_azure_services_bypass - network_rules is
# not rendered with public access disabled; nothing in the plan carries the bypass
```

`core/iac-rendering/scripts/check_render_coverage.py <spec>` reads the spec and the
`tests/` beside it and fails on a decision that is neither asserted nor marked, and on a
marker naming a decision the spec no longer has. Run it with `terraform test`; a render
that passes one and not the other is half done.

Assert the value the spec records, through the attribute `renders` names. A decision
rendered as an absent block (`immutability: none`, `point_in_time_restore_days: 0`,
`key_management: platform_managed`) is asserted as `length(...) == 0` — the absence is the
decision.

A referenced platform (`network_ownership: reference`, `observability_ownership:
reference`) is `data` blocks, and a plan reads those from Azure — so the test would need
credentials after all. Mock the `azurerm` provider for the test and give every mocked data
source an **id that parses**: the provider validates the shape of every id it is handed,
and the random string a bare mock returns fails that validation with a segment-by-segment
error before any assertion runs. The naming provider stays real, so names are asserted as
they will be deployed:

```hcl
mock_provider "azurerm" {
  mock_data "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-hub/subnets/snet-privatelink"
    }
  }
  mock_data "azurerm_log_analytics_workspace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-observability/providers/Microsoft.OperationalInsights/workspaces/log-platform"
    }
  }
}

variables {
  environment = "production"
  location    = "westeurope"
  workload    = "myapp"
  # ...the rest of terraform.tfvars
}

run "storage_account_is_private" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.public_network_access == "Disabled"
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
terraform test
python3 <plugin>/core/iac-rendering/scripts/check_render_coverage.py ./infra-spec.yaml
```

`fmt` is not optional — unformatted generated code is the fastest way to make a reviewer
distrust the rest of it.

`validate` does not warn about a deprecated argument — only the provider schema marks
it. After a provider major version, check the arguments the rendering references name
against `terraform providers schema -json` once rather than trusting the examples.

Then the step that tells you what would actually change:

```bash
terraform plan -out=tfplan
```

Do not report "plan succeeded" as the result. A plan that succeeds and replaces the
production database has succeeded. Read it out: what is created, changed and destroyed;
every `-/+` replacement named with the attribute that forces it; which of the rest a
consumer would notice; and what the plan cannot see — data not migrated, a role assignment
that takes minutes to propagate, a consumer still holding a connection string.
