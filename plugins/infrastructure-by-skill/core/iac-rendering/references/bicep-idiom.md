# Rendering Bicep

How generated Bicep should look. Match the surrounding repository first — if it already has
a layout, follow that and ignore the defaults below.

## File layout

```
main.bicep                  # the deployment entry point
main.bicepparam             # parameters per environment
modules/
  storage.bicep             # one resource concern per file
  storage.network.bicep     # private endpoint, DNS record
types.bicep                 # user-defined types shared across files
infra-spec.yaml
```

A `.bicepparam` file per environment beats one parameter file with conditionals inside it.
The conditionals are where environments silently diverge.

## Modules

Which files exist comes from the spec's `composition` block, not from taste — see
[spec.md](../../iac-authoring/references/spec.md). One `composition.modules` entry is one
file, named after its `id`; a
module needing its own types or several concerns becomes `modules/<id>/main.bicep` instead,
with the rest beside it.

`main.bicep` is the composition: module calls, and the wiring between them. Role
assignments and DNS records that span two modules belong there, because only the caller
can see both.

```bicep
module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    environment: environment
    location: location
    workload: workload
  }
}

module storageNetwork 'modules/storage-network.bicep' = {
  name: 'storage-network'
  params: {
    // The spec's needs: [storage] — an output, never a reach into its resources.
    storageAccountId: storage.outputs.id
    subnetId: subnetId
  }
}
```

### Where Bicep modules differ from Terraform's

Four of these cost a deployment if ported naively from the Terraform side:

- **`name` is the deployment name, not a label.** It must be unique per scope per
  deployment and is capped at 64 characters. Inside a loop it needs a discriminator —
  `name: 'pep-${sub}'` — or the iterations overwrite each other's deployment and only the
  last one's outputs survive.
- **`scope:` is a module property.** Deploying into another resource group or subscription
  is `scope: resourceGroup(otherSub, otherRg)` on the module, where Terraform needs a
  provider alias passed in. This is the asymmetry that makes a cross-scope spec render
  cleanly here and awkwardly there.
- **A module output is not secret.** It is readable in the deployment history, so a module
  never outputs a key or a connection string — pass a Key Vault reference instead.
- **Loops are `for`, and ordering is not an output of the loop.** `[for sub in subs: {…}]`
  on a module is fine; depending on one iteration of it is not.

`dependsOn` is almost never needed: referencing `storage.outputs.id` creates the edge.
Write it only for a dependency Bicep cannot see, with a comment saying what it is.

### Do not generate a module per resource by reflex

`granularity: per-resource` exists for patterns whose parts are reused separately. A
one-resource module whose params restate the resource's properties is a file that adds a
hop and removes nothing.

## Registry references, not relative paths

A spec module with `implementation: reuse` renders as a call to a published module, and
resolving *which* one is this layer's job — the spec deliberately carries no coordinate.
Modules come from the registry through the `br/modules:` alias that `bicepconfig.json`
resolves:

```bicep
module diagnostics 'br/modules:utility/diagnostic:1.0.0' = {
  name: 'diag-${storageAccount.name}'
  params: { /* ... */ }
}
```

Pin the version explicitly — read `version.json` next to the module in
[`LemurDaniel/BICEP__Registry`](https://github.com/LemurDaniel/BICEP__Registry) for what is
current rather than assuming. An unpinned or
floating reference turns a module release into an unannounced change to every consumer.

Relative imports (`'../../schema/module.bicep'`) are correct **inside**
`BICEP__Registry`, where the modules import each other, and wrong everywhere else.
Generating a relative path into a consumer repository produces a file that compiles on one
machine and nowhere else.

If `bicepconfig.json` has no `br/modules` alias, do not invent one. The registry behind it
is a proof of concept and its address is not settled — writing a guessed ACR into a
consumer repository bakes in a PoC that will move. Say the alias is missing and ask where
the modules should come from, or render the resource directly instead of calling a module.

## Referencing a network the deployment does not own

`network_ownership: reference` in the spec means the virtual network is read, never managed.
Bicep spells that `existing`, which compiles to a reference and emits nothing into the
template's resource set:

```bicep
resource platformVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: vnetName
  scope: resourceGroup(networkResourceGroupName)
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: platformVnet
  name: privateEndpointSubnetName
}
```

Note the `scope:` — a platform network usually lives in another resource group, and
without it the lookup silently targets the deployment's own and fails at resolution rather
than at compile time. By name and scope, never by a hardcoded resource id.

With `create`, the same subnet is a resource the deployment owns. Never both: two sources
of truth for one address space.

## Parameters

Every parameter carries `@description`. Constrain what the question set constrained —
`@allowed` for an `enum` question, `@minLength`/`@maxLength` for a string:

```bicep
@description('Deployment environment. Drives the rendered name, the tags and several security defaults.')
@allowed(['development', 'test', 'acceptance', 'production'])
param environment string

@description('Azure region. Defaults to the resource group\'s location.')
param location string = resourceGroup().location
```

Without the `@allowed`, the constraint existed only during the interview and the template
accepts anything.

Prefer a user-defined type over a long flat parameter list once a resource has more than a
handful of knobs — it keeps a resource's inputs in one shape and gives the consumer
something to read:

```bicep
@export()
type storageConfig = {
  @description('Replication. ZRS survives a zone loss at roughly LRS cost.')
  replication: 'LRS' | 'ZRS' | 'GRS' | 'GZRS'

  @description('Days blobs remain restorable after deletion. 0 disables soft delete.')
  blobSoftDeleteDays: int

  privateEndpointSubnetId: string?
}
```

## Names come from vars

The registry's naming modules (`utility/naming/schema`, `utility/naming/generator`,
`genName`) are **not ready to ship** — do not import them and do not call them. On the
Bicep side the name is assembled from `var`s, from the abbreviation the question set
declares plus short codes for location and environment. See [naming.md](naming.md) for the
full pattern and the character limits that come with doing it by hand.

```bicep
var affix = '${locationAbbreviations[location]}${environmentAbbreviations[environment]}'

// Storage accounts: lowercase alphanumeric, no separators, max 24 characters.
var storageAccountName = toLower('st${affix}${workload}${padLeft(index, 2, '0')}')
```

Keep the assembly in one place per deployment and pass the finished name into modules.
Still never hardcode a literal name, and still never scatter the same interpolation across
five resources.

## Tags

One `var`, built once in `main.bicep` and passed into every module as a parameter. Never a
tag literal on a resource — it drifts from its siblings the first time the set changes.

```bicep
@description('Tags applied to every resource in this deployment.')
param tags object

// Deriving anything on top happens once, here, not per module.
var allTags = union(tags, derivedTags)
```

Which tags those are is not a rendering decision — see
[guardrails.md](../../iac-authoring/references/guardrails.md). If the deployment already
has a tags parameter or var, pass that one down instead of adding a second.

## Secure values are explicit

Write them even where they match the API default. A reviewer can see a decision that was
made; an absent property is invisible, and API defaults are not stable across versions.

```bicep
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: { name: 'Standard_ZRS' }
  kind: 'StorageV2'

  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    // Access is via Entra ID and RBAC; keys would bypass both.
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}
```

## API versions

Reuse the API version already used elsewhere in the repository for that resource type. A
newer version is not an improvement by itself, and a template mixing three versions of the
same type is a maintenance problem for no gain.

Never invent one. If no precedent exists in the repository, compile and let Bicep reject an
unknown version — that is a two-second check against a guess that fails at deployment.

## Outputs

Output what a consumer needs to wire against — resource id, principal id of a managed
identity, the rendered name. Never output a key, a connection string or anything else
secret: deployment outputs are readable to anyone with reader on the deployment and persist
in its history.

```bicep
output id string = storageAccount.id
output name string = storageAccount.name
output principalId string = storageAccount.identity.principalId
```

## Before handing over

```bash
bicep format --stdout main.bicep     # or: az bicep format
bicep build --stdout main.bicep      # fails loudly on unknown properties
bicep lint main.bicep
```

Then the deployment-time check, which is the one that matters:

```bash
az deployment group what-if --resource-group <rg> --template-file main.bicep --parameters main.bicepparam
```

`what-if` is Bicep's equivalent of `terraform plan`, the only step that compares against
what is deployed, and it changes nothing — it needs credentials and reader on the resource
group.

Do not report "what-if succeeded" as the result. Read it out: what is created, modified and
deleted; every replacement named with the property that forces it; which of the rest a
consumer would notice; and what `what-if` cannot see — data not migrated, a DNS record the
private endpoint needs, a role assignment that takes minutes to propagate.
