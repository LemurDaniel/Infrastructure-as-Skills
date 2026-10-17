# Rendering a storage account as Bicep

Mapping from the question set to `Microsoft.Storage/storageAccounts`. General layout,
parameter and registry conventions are in
[../../../../core/iac-rendering/references/bicep-idiom.md](../../../../core/iac-rendering/references/bicep-idiom.md).

Compile before handing anything over — `bicep build --stdout` rejects an unknown property
immediately, which beats reasoning about whether it exists:

```bash
bicep build --stdout modules/storage.bicep
```

## Decision → property

| Decision | Property |
|---|---|
| `public_network_access: disabled` | `properties.publicNetworkAccess: 'Disabled'` |
| `public_network_access: enabled_with_firewall` | `'Enabled'` + `networkAcls.defaultAction: 'Deny'` |
| `public_network_access: enabled` | `'Enabled'` + `networkAcls.defaultAction: 'Allow'` |
| `shared_access_key_enabled` | `properties.allowSharedKeyAccess` |
| `https_traffic_only` | `properties.supportsHttpsTrafficOnly` |
| `allow_blob_public_access` | `properties.allowBlobPublicAccess` |
| `min_tls_version` | `properties.minimumTlsVersion` |
| `replication` | `sku.name` — `Standard_ZRS`, `Standard_LRS`, … |
| `access_tier` | `properties.accessTier` |
| `infrastructure_encryption_enabled` | `properties.encryption.requireInfrastructureEncryption` |
| `sftp_enabled` | `properties.isSftpEnabled` (requires `isHnsEnabled: true`) |

Note the shape difference from Terraform: replication is not its own property but encoded
into the SKU name together with the tier, so `Standard` + `ZRS` becomes `Standard_ZRS`.

Soft delete, versioning and the change feed are **not** on the account. They live on the
nested `blobServices/default` resource, which is the most common omission when porting from
Terraform — where `blob_properties` makes them look like account attributes.

## The account

The name is assembled from vars — the Bicep naming modules are not shipped. The pattern and
its parts are in
[../../../../core/iac-rendering/references/naming.md](../../../../core/iac-rendering/references/naming.md).

```bicep
@description('Deployment environment. Drives the rendered name, the tags and several security defaults.')
@allowed(['development', 'test', 'acceptance', 'production'])
param environment string

@description('Azure region. ZRS is unavailable in regions without availability zones.')
param location string = resourceGroup().location

@description('Workload short name, rendered into the resource name.')
param workload string

@description('Replication. ZRS survives a zone loss at roughly LRS cost.')
@allowed(['LRS', 'ZRS', 'GRS', 'GZRS'])
param replication string = 'ZRS'

@description('Instance number, for a second account beside the first.')
param index int = 1

param tags object

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

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'

  sku: {
    name: 'Standard_${replication}'
  }

  identity: {
    type: 'SystemAssigned'
  }

  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false

    // Access is via Entra ID and RBAC. A key would bypass both and is not
    // attributable in the audit log.
    allowSharedKeyAccess: false

    publicNetworkAccess: 'Disabled'
    accessTier: 'Hot'

    encryption: {
      keySource: 'Microsoft.Storage'
      // Settable only at creation — changing it later replaces the account.
      requireInfrastructureEncryption: true
      services: {
        blob: { enabled: true, keyType: 'Account' }
        file: { enabled: true, keyType: 'Account' }
      }
    }

    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}
```

The name is **lowercase alphanumeric, 3–24 characters, no hyphens** — the one Azure
resource where the usual hyphenated form is rejected. With `st` + a 5-character affix + the
2-digit index, `workload` has 15 characters left. `bicep build` will not catch an overlong
one — it is a deploy-time validation failure — so check it while interviewing.

`networkAcls` stays present even with `publicNetworkAccess: 'Disabled'` — the API accepts
it and it documents the intended posture should public access ever be re-enabled. Unlike
Terraform's `network_rules` there is no separate resource to conflict with, so there is no
reason to omit it.

`bypass` is a comma-separated **string**, not an array: `'AzureServices'`, or
`'AzureServices, Logging, Metrics'`, or `'None'`.

## Blob service properties

The nested resource, not the account:

```bicep
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'

  properties: {
    isVersioningEnabled: true
    changeFeed: { enabled: false }

    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }

    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}
```

`days: 0` is not how soft delete is disabled — set `enabled: false`. A policy with
`enabled: true, days: 0` is rejected.

Point-in-time restore goes in the same `properties` as `restorePolicy`, requires
`isVersioningEnabled` and `changeFeed.enabled`, and its `days` must be strictly less than
the blob soft-delete window. The API error for violating that is not specific, so check it
before deploying.

## Private endpoint

One endpoint per sub-resource. The DNS zone is referenced, never created:

```bicep
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = [
  for sub in privateEndpointSubresources: {
    // pep + wedev + objects + blob  ->  pep-wedev-objects-blob
    name: 'pep-${affix}-${workload}-${sub}'
    location: location
    tags: tags

    properties: {
      subnet: { id: privateEndpointSubnetId }
      privateLinkServiceConnections: [
        {
          name: 'psc-${sub}'
          properties: {
            privateLinkServiceId: storageAccount.id
            groupIds: [sub]
          }
        }
      ]
    }
  }
]
```

`groupIds` is Bicep's name for Terraform's `subresource_names`, and likewise takes exactly
one entry per endpoint.

The DNS zone group is a nested child resource of the endpoint
(`privateEndpoints/privateDnsZoneGroups`). Without it the endpoint exists and resolves to
nothing, which presents as a connection timeout rather than a DNS error and is
correspondingly annoying to diagnose.

## Role assignments

Use the `utility/role` module from the registry — it carries the built-in role definition
ids, so the GUID does not get hand-copied:

```bicep
module roleAssignment 'br/modules:utility/role:1.0.0' = {
  name: 'ra-${storageAccount.name}-blob'
  params: {
    principalId: consumerPrincipalId
    roleDefinitionName: 'Storage Blob Data Contributor'
    scope: storageAccount.id
  }
}
```

Check `var.builtIn.bicep` in that module for the available role names before using one.

Data access needs the **data-plane** roles — `Storage Blob Data Reader`,
`Storage Blob Data Contributor`. `Contributor` is control-plane and grants no data access
whatsoever, which is worth catching in review: an application given `Contributor` on a
storage account still cannot read a blob.

## Diagnostics

Use the `utility/diagnostic` module rather than hand-writing the setting:

```bicep
module diagnostics 'br/modules:utility/diagnostic:1.0.0' = {
  name: 'diag-${storageAccount.name}'
  params: {
    targetResourceId: storageAccount.id
    workspaceId: diagnosticWorkspaceId
    categoryGroups: diagnosticCategories
  }
}
```

Check the module's parameter names against its own `module.bicep` before generating — this
is a local module and its interface is not a public contract.

Blob data-plane logs attach to `${storageAccount.id}/blobServices/default`, not to the
account. A setting on the account alone collects no `StorageRead` or `StorageWrite` events
while looking fully configured.

## Outputs

```bicep
output id string = storageAccount.id
output name string = storageAccount.name
output principalId string = storageAccount.identity.principalId
```

Never output a key or a connection string. Deployment outputs persist in the deployment
history and are readable to anyone with reader on the resource group.
