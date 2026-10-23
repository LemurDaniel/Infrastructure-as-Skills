# Rendering a Cosmos DB account as Bicep

Mapping from the question set to the account. General layout, parameters and naming are in
[../../../core/iac-rendering/references/bicep-idiom.md](../../../core/iac-rendering/references/bicep-idiom.md).

```bash
bicep build --stdout modules/cosmos-db.bicep
```

## With the AVM module

| Module | Documented against | Resolved |
|---|---|---|
| `br/public:avm/res/document-db/database-account:<version>` | **0.21.1** | 2026-10-23 |

Resolve the current version and re-read the README parameters before rendering, as
[avm.md](../../../core/iac-rendering/references/avm.md) says. Pin the exact version.

### Decision -> module parameter

| Decision | Parameter | Note |
|---|---|---|
| `capacity_mode` | `capacityMode: 'Provisioned'` / `'Serverless'` | Default `'Provisioned'`; written |
| `throughput_mode`, `max_throughput` | on each container: `autoscaleSettingsMaxThroughput` or `throughput` | |
| `total_throughput_limit` | `totalThroughputLimit` | |
| `free_tier` | `enableFreeTier` | |
| `zone_redundant`, `geo_replicas` | `failoverLocations: [ { locationName, failoverPriority, isZoneRedundant } ]`; a single region may use `zoneRedundant` | `zoneRedundant` default **true**, ignored for several regions; written |
| `automatic_failover` | `enableAutomaticFailover` | Default `true`; written |
| `consistency_level` | `defaultConsistencyLevel` | Default `'Session'`; differs from Terraform; written |
| `public_network_access` | `networkRestrictions: { publicNetworkAccess: 'Disabled', ipRules, networkAclBypass }` | Default disabled; written |
| `network_acl_bypass` | `networkRestrictions.networkAclBypass: 'None'` / `'AzureServices'` | A string here, a bool in Terraform |
| `private_endpoint_subnet` | `privateEndpoints: [ { subnetResourceId, service: 'Sql' } ]` | |
| `deployment.private_dns_records: policy` | no `privateDnsZoneGroup` on the endpoint | |
| `managed_identity` | `managedIdentities: { systemAssigned, userAssignedResourceIds }` | |
| `role_assignments` | `roleAssignments` | Control plane |
| `data_plane_role_assignments` | `sqlRoleAssignments: [ { principalId, roleDefinitionId, scope } ]` | `roleDefinitionId` is the full id of the built-in definition under the account |
| `local_authentication_disabled` | `disableLocalAuthentication` | Default `true`; written |
| `key_based_metadata_writes` | `disableKeyBasedMetadataWriteAccess` | Default `true`; written |
| `key_management`, `cmk_key_vault_key_id` | `customerManagedKey: { keyName, keyVaultResourceId, userAssignedIdentityResourceId }` | Unversioned |
| `backup_policy` | `backupPolicyType`, `backupPolicyContinuousTier` | Default `'Continuous'` / `'Continuous30Days'` |
| `backup_storage_redundancy` | `backupStorageRedundancy` | Default **`'Local'`**; differs from Terraform; written |
| `analytical_storage` | `enableAnalyticalStorage` | |
| `databases` | `sqlDatabases: [ { name, containers: [ { name, paths, defaultTtl, autoscaleSettingsMaxThroughput } ] } ]` | |
| diagnostics | `diagnosticSettings: [ { workspaceResourceId, logCategoriesAndGroups: [ { category } ], metricCategories: [ { category: 'AllMetrics' } ] } ]` | |
| `deployment.module_telemetry` | `enableTelemetry` | |
| `context.tags` | `tags` | |

### The call

```bicep
module cosmos 'br/public:avm/res/document-db/database-account:0.21.1' = {
  name: 'cosmos-db'
  params: {
    name: cosmosName
    location: location
    tags: tags

    capacityMode: 'Provisioned'
    enableFreeTier: false
    totalThroughputLimit: -1

    // decision: cosmos-db.resilience.zone_redundant
    failoverLocations: [
      { locationName: location, failoverPriority: 0, isZoneRedundant: true }
    ]
    enableAutomaticFailover: true
    // decision: cosmos-db.resilience.consistency_level - differs from the Terraform default
    defaultConsistencyLevel: 'Session'

    // decision: cosmos-db.networking.public_network_access
    networkRestrictions: {
      publicNetworkAccess: 'Disabled'
      networkAclBypass: 'None'
      ipRules: []
    }
    privateEndpoints: [
      {
        name: privateEndpointName
        service: 'Sql'
        subnetResourceId: privateEndpointSubnetId
        // private_dns_records: policy - no zone group, the platform policy writes the record
      }
    ]

    disableLocalAuthentication: true
    disableKeyBasedMetadataWriteAccess: true

    // decision: cosmos-db.data_protection.backup_policy
    backupPolicyType: 'Continuous'
    backupPolicyContinuousTier: 'Continuous7Days'
    enableAnalyticalStorage: false

    sqlDatabases: [
      {
        name: 'app'
        containers: [
          {
            name: 'conversations'
            paths: [ '/userId' ]
            autoscaleSettingsMaxThroughput: 1000
          }
        ]
      }
    ]

    sqlRoleAssignments: sqlRoleAssignments

    diagnosticSettings: [
      {
        workspaceResourceId: diagnosticWorkspaceId
        logCategoriesAndGroups: [
          { category: 'ControlPlaneRequests' }
          { category: 'DataPlaneRequests' }
        ]
        metricCategories: [ { category: 'AllMetrics' } ]
      }
    ]
    enableTelemetry: true
  }
}

output id string = cosmos.outputs.resourceId
output endpoint string = cosmos.outputs.endpoint
```

The built-in data roles are `<account id>/sqlRoleDefinitions/00000000-0000-0000-0000-000000000001`
(reader) and `...0002` (contributor); the exact shape of `sqlRoleAssignments` is read from the
README of the pinned version.

### Tests

A module call compiles to a nested deployment whose `properties.parameters.<param>.value` is
the decision, so every decision above is observable in `tests/*.armtest.yaml`
([bicep-idiom.md](../../../core/iac-rendering/references/bicep-idiom.md#tests)), including the
containers and the data-plane roles, which the Terraform side cannot see through the module.

## Authored rendering

The fallback. `Microsoft.DocumentDB/databaseAccounts` with `kind: 'GlobalDocumentDB'`:

| Decision | Property |
|---|---|
| `capacity_mode` | `properties.capabilities: [ { name: 'EnableServerless' } ]` |
| `zone_redundant`, `geo_replicas` | `properties.locations[].isZoneRedundant`, `failoverPriority` |
| `consistency_level` | `properties.consistencyPolicy.defaultConsistencyLevel` |
| `public_network_access` | `properties.publicNetworkAccess`, `ipRules`, `networkAclBypass` |
| `local_authentication_disabled` | `properties.disableLocalAuth` |
| `key_based_metadata_writes` | `properties.disableKeyBasedMetadataWriteAccess` |
| `backup_policy` | `properties.backupPolicy: { type, continuousModeProperties.tier }` |
| `key_management` | `properties.keyVaultKeyUri` (versionless) and `defaultIdentity` |
| `databases` | child `sqlDatabases` and `sqlDatabases/containers` |
| `data_plane_role_assignments` | child `sqlRoleAssignments` |
