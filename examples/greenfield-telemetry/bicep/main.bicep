// Rendered from ../infra-spec.yaml (target: bicep). composition.granularity: single, so
// one root: one Azure Verified Module call per resource and the wiring between them.
// deployment.landing_zone: standalone - the deployment owns its network, its privatelink
// zone and its workspace; nothing is referenced.
// Versions resolved 2026-10-18 from the MCR tag lists: virtual-network 0.10.2,
// operational-insights/workspace 0.16.1, private-dns-zone 0.8.1, storage-account 0.33.1.
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

// ------------------------------ storage account decisions the caller may still vary

@description('Storage services that get a private endpoint. One endpoint, one privatelink zone and one record per entry, so list only what is used.')
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
  germanywestcentral: 'gwc'
}

var loc = locationCodes[location]
var env = environmentCodes[environment]
var idx = padLeft(index, 2, '0')

// patterns.Azure."Microsoft.Network/virtualNetworks": <TYPE>-<LOCATION>-<ENVIRONMENT>-<NAME>-<INDEX>
var virtualNetworkName = 'vnet-${loc}-${env}-${workload}-${idx}'
// patterns.Azure."Microsoft.Network/virtualNetworks/subnets": <TYPE>-<ENVIRONMENT>-<NAME>-<INDEX>
var privateEndpointSubnetName = 'snet-${env}-privatelink-${idx}'
// patterns.Azure.default: <TYPE>-<LOCATION>-<ENVIRONMENT>-<NAME><?SUBNAME;-%s>-<INDEX>
var workspaceName = 'log-${loc}-${env}-${workload}-${idx}'
var privateEndpointNames = [for sub in privateEndpointSubresources: 'pep-${loc}-${env}-${workload}-${sub}-${idx}']
// patterns.Azure."Microsoft.Storage/storageAccounts": <TYPE><LOCATION><ENVIRONMENT><NAME><INDEX>, lowercase
var storageAccountName = toLower('st${loc}${env}${workload}${idx}')

// The privatelink zone per storage sub-resource. Fixed names, Azure's - az.environment(),
// because the environment parameter shadows the function.
var privateDnsZoneNames = {
  blob: 'privatelink.blob.${az.environment().suffixes.storage}'
  file: 'privatelink.file.${az.environment().suffixes.storage}'
  queue: 'privatelink.queue.${az.environment().suffixes.storage}'
  table: 'privatelink.table.${az.environment().suffixes.storage}'
  dfs: 'privatelink.dfs.${az.environment().suffixes.storage}'
  web: 'privatelink.web.${az.environment().suffixes.storage}'
}

// ----------------------------------------------------------- observability
// observability_ownership: create - the deployment's own workspace, and the destination
// of every diagnostic setting below. First, because everything else points at it.

module workspace 'br/public:avm/res/operational-insights/workspace:0.16.1' = {
  name: 'observability'
  params: {
    name: workspaceName
    location: location
    tags: tags

    // decision: log-analytics-workspace.cost.sku
    skuName: 'PerGB2018'
    // decision: log-analytics-workspace.cost.retention_days - stated 90; the module default is 365
    dataRetention: 90
    // decision: log-analytics-workspace.cost.daily_quota_gb - a string on this module, -1 is no cap
    dailyQuotaGb: '-1'

    // decision: log-analytics-workspace.access.public_network_access - both, or logs arrive
    // and nobody can read them. The module defaults are Enabled. Reading the logs now
    // needs an Azure Monitor Private Link Scope, which this deployment does not create.
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Disabled'

    features: {
      // decision: log-analytics-workspace.access.local_auth - the workspace key is a
      // non-expiring bearer credential.
      disableLocalAuth: true
      // decision: log-analytics-workspace.access.rbac_only_access - false here means RBAC
      // on the workspace governs reads, not permissions inherited from the emitting resource.
      enableLogAccessUsingOnlyResourcePermissions: false
    }

    enableTelemetry: true // deployment.module_telemetry: enabled
  }
}

// ----------------------------------------------------------------- network
// network_ownership: create - standalone, no peering. The private-endpoint subnet is
// first in the list, so subnetResourceIds[0] is the one the endpoints attach to.

module virtualNetwork 'br/public:avm/res/network/virtual-network:0.10.2' = {
  name: 'network'
  params: {
    name: virtualNetworkName
    location: location
    tags: tags

    // decision: virtual-network.addressing.address_space
    addressPrefixes: ['10.20.0.0/16']

    // decision: virtual-network.addressing.subnets
    subnets: [
      {
        name: privateEndpointSubnetName
        // decision: virtual-network.addressing.private_endpoint_subnet_prefix
        addressPrefix: '10.20.1.0/27'
        // decision: virtual-network.subnet_policy.private_endpoint_network_policies - NSG
        // and routes apply to endpoint traffic.
        privateEndpointNetworkPolicies: 'Enabled'
        // decision: virtual-network.subnet_policy.service_endpoints - none: the weaker posture
        serviceEndpoints: []
      }
      {
        name: 'snet-app'
        addressPrefix: '10.20.2.0/24'
        privateEndpointNetworkPolicies: 'Enabled'
        serviceEndpoints: []
      }
    ]
    // decision: virtual-network.addressing.dns_servers - empty: Azure DNS, which resolves
    // the privatelink zone linked below without further setup.
    dnsServers: []

    // decision: virtual-network.observability.diagnostic_workspace
    diagnosticSettings: [
      {
        name: 'diag'
        workspaceResourceId: workspace.outputs.resourceId
        metricCategories: [{ category: 'AllMetrics' }]
      }
    ]

    enableTelemetry: true // deployment.module_telemetry: enabled
  }
}

// --------------------------------------------------------------------- dns
// private_dns_ownership: deployment (forced by landing_zone: standalone) - the root owns
// one privatelink zone per endpoint sub-resource and links it to the network it created.
// The record itself is written by the endpoint's zone group on the storage module.

module privateDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.1' = [
  for sub in privateEndpointSubresources: {
    name: 'dns-${sub}'
    params: {
      name: privateDnsZoneNames[sub]
      location: 'global'
      tags: tags
      virtualNetworkLinks: [
        {
          virtualNetworkResourceId: virtualNetwork.outputs.resourceId
          // No VM records in a privatelink zone - only the endpoint records.
          registrationEnabled: false
        }
      ]
      enableTelemetry: true // deployment.module_telemetry: enabled
    }
  }
]

// ----------------------------------------------------------------- storage

module storageAccount 'br/public:avm/res/storage/storage-account:0.33.1' = {
  name: 'storage'
  params: {
    name: storageAccountName
    location: location
    tags: tags
    kind: 'StorageV2'
    // decision: storage-account.data_protection.replication - derived from outage_impact;
    // the module default is Standard_GRS
    skuName: 'Standard_ZRS'
    // decision: storage-account.data_protection.access_tier - derived from data_access_pattern
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
    // Access is via Entra ID and RBAC. A key would bypass both.
    allowSharedKeyAccess: false
    enableSftp: false
    // Settable only at creation.
    requireInfrastructureEncryption: true

    managedIdentities: {
      systemAssigned: true
    }

    // Soft delete, versioning and the change feed live on the blob service - derived
    // from data_loss_tolerance: one_week. The blob data-plane logs go with them.
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
          workspaceResourceId: workspace.outputs.resourceId
          logCategoriesAndGroups: [{ categoryGroup: 'audit' }]
          metricCategories: [{ category: 'AllMetrics' }]
        }
      ]
    }

    // One endpoint per sub-resource, into the private-endpoint subnet this deployment
    // created. private_dns_records is not reached under private_dns_ownership: deployment -
    // the zone group here writes the record into the zone the root created above.
    privateEndpoints: [
      for (sub, i) in privateEndpointSubresources: {
        name: privateEndpointNames[i]
        service: sub
        subnetResourceId: virtualNetwork.outputs.subnetResourceIds[0]
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: privateDnsZone[i].outputs.resourceId
            }
          ]
        }
      }
    ]

    // The account itself emits metrics only; the parameter is typed that way.
    diagnosticSettings: [
      {
        name: 'diag'
        workspaceResourceId: workspace.outputs.resourceId
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

output workspaceId string = workspace.outputs.resourceId
output virtualNetworkId string = virtualNetwork.outputs.resourceId
output privateEndpointSubnetId string = virtualNetwork.outputs.subnetResourceIds[0]
output storageAccountId string = storageAccount.outputs.resourceId
output storageAccountName string = storageAccount.outputs.name

@description('System-assigned identity of the account, for grants it needs outward.')
output storagePrincipalId string = storageAccount.outputs.?systemAssignedMIPrincipalId ?? ''
