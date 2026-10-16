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

## Registry references, not relative paths

Modules come from the registry through the `br/modules:` alias that `bicepconfig.json`
resolves:

```bicep
import { schema } from 'br/modules:utility/naming/schema:5.5.0'
import { genName } from 'br/modules:utility/naming/generator:5.5.0'

module diagnostics 'br/modules:utility/diagnostic:1.0.0' = {
  name: 'diag-${storageAccount.name}'
  params: { /* ... */ }
}
```

Pin the version explicitly — read `version.json` next to the module in
`BICEP__Module-Registry` for what is current rather than assuming. An unpinned or
floating reference turns a module release into an unannounced change to every consumer.

Relative imports (`'../../schema/module.bicep'`) are correct **inside**
`BICEP__Module-Registry`, where the modules import each other, and wrong everywhere else.
Generating a relative path into a consumer repository produces a file that compiles on one
machine and nowhere else.

If `bicepconfig.json` has no `br/modules` alias, add it rather than working around it:

```json
{
  "moduleAliases": {
    "br": {
      "modules": { "registry": "bicepnamingpoc001.azurecr.io" }
    }
  }
}
```

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

## Names come from the engine

Via `genName` / `genNameId`, never assembled by hand. Note the Bicep identifier has **no**
`Azure::` prefix — that is Terraform-only. See [naming.md](naming.md).

```bicep
var storageAccountName = genName('Microsoft.Storage/storageAccounts', schema.default, location, {
  name: workload
  environment: environment
})
```

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

`what-if` is Bicep's equivalent of `terraform plan` and the only step that tells you what
would actually change. See [iac-plan-review](../../iac-plan-review/SKILL.md).
