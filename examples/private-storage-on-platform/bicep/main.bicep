// Rendered from ../infra-spec.yaml (target: bicep). composition.granularity: single,
// so one root and no modules of its own - the same decisions the Terraform render
// beside it carries. deployment.module_source: avm, so the account is one call to
// br/public:avm/res/storage/storage-account, every decision an explicit parameter.
// Version resolved 2026-10-18 from the MCR tag list: 0.33.1.
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

@description('Data-plane role assignments on the account, role by name. Empty means a working account nobody can read - open in the spec until the consumer is named.')
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

module storageAccount 'br/public:avm/res/storage/storage-account:0.33.1' = {
  name: 'storage'
  params: {
    name: storageAccountName
    location: location
    tags: tags
    kind: 'StorageV2'
    // decision: storage-account.data_protection.replication - the module default is Standard_GRS
    skuName: 'Standard_ZRS'
    // decision: storage-account.data_protection.access_tier
    accessTier: 'Hot'

    // decision: storage-account.networking.public_network_access
    publicNetworkAccess: 'Disabled'
    // Present although public access is off: documents the posture, and the bypass is a
    // recorded decision (storage-account.networking.allow_azure_services_bypass).
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }

    // Explicit although several match the module default: a reviewer reads the call,
    // not the module, and a module version can move a default.
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    // Access is via Entra ID and RBAC. A key would bypass both and is not
    // attributable in the audit log.
    allowSharedKeyAccess: false
    enableSftp: false
    // Settable only at creation - changing it later replaces the account.
    requireInfrastructureEncryption: true

    managedIdentities: {
      systemAssigned: true
    }

    // Soft delete, versioning and the change feed live on the blob service - the module
    // nests them, and the blob data-plane logs go with them. The account itself emits
    // no log categories, so its own diagnosticSettings below carry metrics only.
    blobServices: {
      isVersioningEnabled: true
      changeFeedEnabled: false
      deleteRetentionPolicyEnabled: true
      deleteRetentionPolicyDays: 7
      containerDeleteRetentionPolicyEnabled: true
      containerDeleteRetentionPolicyDays: 7
      diagnosticSettings: [
        {
          name: 'diag'
          workspaceResourceId: platformWorkspace.id
          logCategoriesAndGroups: [{ categoryGroup: 'audit' }]
          metricCategories: [{ category: 'AllMetrics' }]
        }
      ]
    }

    // One endpoint per sub-resource, into the platform's private-endpoint subnet.
    // deployment.private_dns_records: policy - no privateDnsZoneGroup; the landing
    // zone's DeployIfNotExists policy attaches the zone and writes the record.
    privateEndpoints: [
      for (sub, i) in privateEndpointSubresources: {
        name: privateEndpointNames[i]
        service: sub
        subnetResourceId: privateEndpointSubnet.id
      }
    ]

    diagnosticSettings: [
      {
        name: 'diag'
        workspaceResourceId: platformWorkspace.id
        metricCategories: [{ category: 'AllMetrics' }]
      }
    ]

    // Data-plane roles on the account, by name. Empty until the consumer is named (spec: open).
    roleAssignments: [
      for ra in roleAssignments: {
        principalId: ra.principalId
        roleDefinitionIdOrName: ra.role
      }
    ]

    enableTelemetry: true // deployment.module_telemetry: enabled
  }
}

// ----------------------------------------------------------------- outputs

output id string = storageAccount.outputs.resourceId
output name string = storageAccount.outputs.name

@description('System-assigned identity of the account, for grants it needs outward.')
output principalId string = storageAccount.outputs.?systemAssignedMIPrincipalId ?? ''

@description('Private endpoints as the module reports them, one per sub-resource.')
output privateEndpoints array = storageAccount.outputs.privateEndpoints
