# Rendering a storage account as Bicep

Mapping from the question set to `Microsoft.Storage/storageAccounts`. General layout,
parameter and registry conventions are in
[../../../core/iac-rendering/references/bicep-idiom.md](../../../core/iac-rendering/references/bicep-idiom.md).

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
[../../../core/iac-rendering/references/naming.md](../../../core/iac-rendering/references/naming.md).

```bicep
@description('Deployment environment. Drives the rendered name, the tags and several security defaults.')
@allowed(['development', 'test', 'staging', 'production']) // keys of mappings.environment in use
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

// Generated from naming.yaml (mappings). Regenerate, do not edit here.
var environmentCodes = {
  development: 'dev'
  test: 'tst'
  staging: 'stg'
  production: 'prod'
}
var locationCodes = {
  westeurope: 'we'
  germanywestcentral: 'gwc'
}

// patterns.Azure."Microsoft.Storage/storageAccounts":
// <TYPE><LOCATION><ENVIRONMENT><NAME><INDEX>, lowercase  ->  stwedevobjects01
var storageAccountName = toLower('st${locationCodes[location]}${environmentCodes[environment]}${workload}${padLeft(index, 2, '0')}')

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
    // patterns.Azure.default with <?SUBNAME>  ->  pep-we-dev-objects-blob-01
    name: 'pep-${locationCodes[location]}-${environmentCodes[environment]}-${workload}-${sub}-${padLeft(index, 2, '0')}'
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
(`privateEndpoints/privateDnsZoneGroups`), and **who writes it is
`deployment.private_dns_records`**:

- `policy` — the landing-zone default. A DeployIfNotExists policy attaches the zone group
  after deployment. Render **no** zone group; a second writer re-creates the conflict on
  every deployment.
- `deployment` — render it, with the zone referenced from the hub subscription
  (`private_dns_zone_scope`):

```bicep
resource zoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = [
  for (sub, i) in privateEndpointSubresources: if (privateDnsRecords == 'deployment') {
    parent: privateEndpoint[i]
    name: 'default'
    properties: {
      privateDnsZoneConfigs: [
        { name: sub, properties: { privateDnsZoneId: privateDnsZoneIds[sub] } }
      ]
    }
  }
]
```

Either way something must write the record. Without it the endpoint exists and resolves to
nothing, which presents as a connection timeout rather than a DNS error — so under
`policy`, confirm the policy is actually assigned to the landing zone.

## Role assignments

With a `br/modules` alias in `bicepconfig.json`, the registry's `utility/role` module
carries the built-in role definition ids (check its `var.builtIn.bicep` for the names).
Without one — the usual case in a fresh consumer repository — do not invent the alias;
render the assignment directly, with the ids of the data-plane roles the question set
allows kept in one map. The GUIDs are Azure's built-in ones, identical in every tenant:

```bicep
type roleAssignment = {
  principalId: string
  role: 'Storage Blob Data Reader' | 'Storage Blob Data Contributor' | 'Storage Blob Data Owner'
}

var roleDefinitionIds = {
  'Storage Blob Data Reader': '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
  'Storage Blob Data Contributor': 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  'Storage Blob Data Owner': 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
}

resource dataRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for ra in roleAssignments: {
    name: guid(storageAccount.id, ra.principalId, ra.role)
    scope: storageAccount
    properties: {
      principalId: ra.principalId
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionIds[ra.role])
    }
  }
]
```

`name` must be a deterministic GUID — `guid()` over the scope, principal and role — or a
second deployment creates a second assignment. The union type on `role` is what Terraform's
`role_definition_name` string lacks: a typo there is an apply-time error, here a compile
error.

Data access needs the **data-plane** roles — `Storage Blob Data Reader`,
`Storage Blob Data Contributor`. `Contributor` is control-plane and grants no data access
whatsoever, which is worth catching in review: an application given `Contributor` on a
storage account still cannot read a blob.

## Diagnostics

Two settings, because the account and its blob service are two diagnostic targets. The
account itself emits **no log categories** — a `logs` entry on the account is rejected at
deployment — so `diagnostic_categories` renders on the blob service and the account gets
metrics only. The same split as the Terraform render, which is the point:

```bicep
resource storageDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag'
  scope: storageAccount
  properties: {
    workspaceId: platformWorkspace.id
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

// Blob data-plane logs attach to blobServices/default. A setting on the account
// alone collects no StorageRead/Write/Delete while looking configured.
resource blobDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag'
  scope: blobService
  properties: {
    workspaceId: platformWorkspace.id
    logs: [
      { categoryGroup: 'audit', enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}
```

`scope:` on the setting is the Bicep spelling of Terraform's `target_resource_id`; pointing
it at the nested `blobService` resource is what appends `/blobServices/default`. With a
`br/modules` alias the registry's `utility/diagnostic` module can replace the two blocks —
check its `module.bicep` for the parameter names first, its interface is not a public
contract — but never invent the alias to use it.

## Outputs

```bicep
output id string = storageAccount.id
output name string = storageAccount.name
output principalId string = storageAccount.identity.principalId
```

Never output a key or a connection string. Deployment outputs persist in the deployment
history and are readable to anyone with reader on the resource group.
