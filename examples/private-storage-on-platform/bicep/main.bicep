// Rendered from ../infra-spec.yaml (target: bicep). composition.granularity: single,
// so one root and no modules - the same decisions the Terraform render beside it carries.
targetScope = 'resourceGroup'

// ---------------------------------------------------------------- context

@description('Deployment environment. Drives the rendered name, the tags and several security defaults.')
@allowed([
  'development'
  'test'
  'qa'
  'uat'
  'integration'
  'staging'
  'preproduction'
  'production'
  'sandbox'
  'demo'
  'hotfix'
]) // keys of mappings.environment in naming.yaml
param environment string

@description('Azure region. Part of every rendered name, so it must be mapped in naming.yaml.')
param location string = resourceGroup().location

@description('Workload short name, rendered into every resource name. 15 characters at most, or the storage account name exceeds 24.')
@maxLength(15)
param workload string

@description('Instance number, for a second instance beside the first.')
param index int = 1

@description('The organisation\'s tag set, applied to every resource. Open in the spec: nothing stated yet.')
param tags object = {}

// ---------------------------- platform the deployment references, never manages

@description('Existing hub virtual network holding the private-endpoint subnet (deployment.existing_vnet).')
param vnetName string

@description('Resource group of the hub virtual network.')
param networkResourceGroupName string

@description('Existing subnet in the hub that carries the deployment\'s private endpoints (deployment.private_endpoint_subnet).')
param privateEndpointSubnetName string

@description('Existing central Log Analytics workspace receiving diagnostics (deployment.diagnostics_destination).')
param workspaceName string

@description('Resource group of the central Log Analytics workspace.')
param workspaceResourceGroupName string

// ------------------------------ storage account decisions the caller may still vary

@description('Storage services that get a private endpoint. One endpoint and one DNS record per entry, so list only what is used.')
@allowed(['blob', 'file', 'queue', 'table', 'dfs', 'web'])
param privateEndpointSubresources string[] = ['blob']

@description('Data-plane role assignments on the account. Empty means a working account nobody can read - open in the spec until the consumer is named.')
param roleAssignments roleAssignment[] = []

type roleAssignment = {
  @description('Object id of the principal.')
  principalId: string
  @description('Data-plane role. Contributor and Owner are control-plane and grant no data access.')
  role: 'Storage Blob Data Reader' | 'Storage Blob Data Contributor' | 'Storage Blob Data Owner'
}

// ------------------------------------------------------------------ naming
// Generated from naming.yaml (mappings, patterns, abbreviations). Regenerate, do not edit here.

var environmentCodes = {
  development: 'dev'
  staging: 'stg'
  test: 'tst'
  production: 'prod'
  integration: 'int'
  sandbox: 'sbx'
  preproduction: 'preprod'
  uat: 'uat'
  qa: 'qa'
  demo: 'demo'
  hotfix: 'hf'
}
var locationCodes = {
  westeurope: 'we'
}

var loc = locationCodes[location]
var env = environmentCodes[environment]
var idx = padLeft(index, 2, '0')

// patterns.Azure."Microsoft.Storage/storageAccounts": <TYPE><LOCATION><ENVIRONMENT><NAME><INDEX>, lowercase
var storageAccountName = toLower('st${loc}${env}${workload}${idx}')

// patterns.Azure.default: <TYPE>-<LOCATION>-<ENVIRONMENT>-<NAME><?SUBNAME;-%s>-<INDEX>
var privateEndpointNames = [for sub in privateEndpointSubresources: 'pep-${loc}-${env}-${workload}-${sub}-${idx}']

// Built-in data-plane roles. The GUIDs are Azure's, identical in every tenant.
var roleDefinitionIds = {
  'Storage Blob Data Reader': '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
  'Storage Blob Data Contributor': 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  'Storage Blob Data Owner': 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
}

// ---------------------------------------------------------------- platform
// existing: compiled to references, never managed (network_ownership: reference,
// observability_ownership: reference). By name and scope, never by a hardcoded id.

resource platformVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
  scope: resourceGroup(networkResourceGroupName)
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: platformVnet
  name: privateEndpointSubnetName
}

resource platformWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
  scope: resourceGroup(workspaceResourceGroupName)
}

// ----------------------------------------------------------------- storage

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'

  // Replication is encoded into the SKU name together with the tier.
  sku: {
    name: 'Standard_ZRS'
  }

  identity: {
    type: 'SystemAssigned'
  }

  properties: {
    accessTier: 'Hot'

    // Explicit although several match the API default: a reviewer can see a
    // decision that was made, and an API version cannot move it.
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Disabled'

    // Access is via Entra ID and RBAC. A key would bypass both and is not
    // attributable in the audit log.
    allowSharedKeyAccess: false
    isSftpEnabled: false

    encryption: {
      keySource: 'Microsoft.Storage'
      // Settable only at creation - changing it later replaces the account.
      requireInfrastructureEncryption: true
      services: {
        blob: { enabled: true, keyType: 'Account' }
        file: { enabled: true, keyType: 'Account' }
      }
    }

    // Present although public access is off: it documents the posture should
    // public access ever be re-enabled, and the trusted-services bypass is a
    // recorded decision (allow_azure_services_bypass: true).
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

// Soft delete, versioning and the change feed live on the blob service, not the account.
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

// ----------------------------------------------------------------- network
// One endpoint per sub-resource, into the platform's private-endpoint subnet.
// deployment.private_dns_records: policy - the landing zone's DeployIfNotExists
// policy attaches the privatelink zone and writes the record. No zone group
// here, or two writers own one record.

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = [
  for (sub, i) in privateEndpointSubresources: {
    name: privateEndpointNames[i]
    location: location
    tags: tags

    properties: {
      subnet: { id: privateEndpointSubnet.id }
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

// ----------------------------------------------------------- observability
// Two settings, because the account and its blob service are two diagnostic
// targets: the account itself emits no log categories.

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

// ------------------------------------------------------------------ access
// Data-plane roles on the account. Empty until the consumer is named (spec: open).

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

// ----------------------------------------------------------------- outputs

output id string = storageAccount.id
output name string = storageAccount.name

@description('System-assigned identity of the account, for grants it needs outward.')
output principalId string = storageAccount.identity.principalId

@description('Private endpoint id per sub-resource. An array, not an object: Bicep cannot index a resource loop from inside a lambda (BCP247).')
output privateEndpoints array = [
  for (sub, i) in privateEndpointSubresources: { subresource: sub, id: privateEndpoint[i].id }
]
