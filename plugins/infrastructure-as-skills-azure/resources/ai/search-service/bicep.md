# Rendering an AI Search service as Bicep

Mapping from the question set to the service. General layout, parameters and naming are in
[../../../core/iac-rendering/references/bicep-idiom.md](../../../core/iac-rendering/references/bicep-idiom.md).

```bash
bicep build --stdout modules/search-service.bicep
```

## With the AVM module

| Module | Documented against | Resolved |
|---|---|---|
| `br/public:avm/res/search/search-service:<version>` | **0.13.0** | 2026-10-23 |

Resolve the current version and re-read the README parameters before rendering, as
[avm.md](../../../core/iac-rendering/references/avm.md) says. Pin the exact version.

### Decision -> module parameter

| Decision | Parameter | Note |
|---|---|---|
| `sku` | `sku` | Default `'standard'`; written |
| `replica_count` | `replicaCount` | Default **3** (Terraform: 1); written |
| `partition_count` | `partitionCount` | Default 1; written |
| `semantic_ranker` | `semanticSearch: 'disabled'` / `'free'` / `'standard'` | |
| `public_network_access` | `publicNetworkAccess: 'Disabled'` / `'Enabled'` | Default **`'Enabled'`** |
| `ip_rules`, `network_rule_bypass` | `networkRuleSet: { ipRules: [ { value } ], bypass }` | Member names from the README |
| `private_endpoint_subnet` | `privateEndpoints: [ { subnetResourceId, service: 'searchService' } ]` | |
| `deployment.private_dns_records: policy` | no `privateDnsZoneGroup` on the endpoint | |
| `managed_identity` | `managedIdentities: { systemAssigned, userAssignedResourceIds }` | |
| `role_assignments` | `roleAssignments` | |
| `local_authentication_disabled` | `disableLocalAuth` | Default `true`; written. `authOptions` is ignored while it is true |
| `cmk_enforcement` | `cmkEnforcement: 'Enabled'` / `'Disabled'` / `'Unspecified'` | Default `'Unspecified'`; written |
| diagnostics | `diagnosticSettings: [ { workspaceResourceId, logCategoriesAndGroups: [ { category } ], metricCategories: [ { category: 'AllMetrics' } ] } ]` | |
| `deployment.module_telemetry` | `enableTelemetry` | |
| `context.tags` | `tags` | |

### The call

```bicep
module search 'br/public:avm/res/search/search-service:0.13.0' = {
  name: 'search-service'
  params: {
    name: searchName
    location: location
    tags: tags

    sku: 'standard'
    // decision: search-service.service.replica_count - the module default is 3
    replicaCount: 2
    partitionCount: 1
    semanticSearch: 'free'

    // decision: search-service.networking.public_network_access - the module default is Enabled
    publicNetworkAccess: 'Disabled'
    networkRuleSet: {
      bypass: 'None'
      ipRules: []
    }
    privateEndpoints: [
      {
        name: privateEndpointName
        service: 'searchService'
        subnetResourceId: privateEndpointSubnetId
        // private_dns_records: policy - no zone group, the platform policy writes the record
      }
    ]

    managedIdentities: { systemAssigned: true }
    // decision: search-service.security.local_authentication_disabled
    disableLocalAuth: true
    roleAssignments: roleAssignments

    diagnosticSettings: [
      {
        workspaceResourceId: diagnosticWorkspaceId
        logCategoriesAndGroups: [ { category: 'OperationLogs' } ]
        metricCategories: [ { category: 'AllMetrics' } ]
      }
    ]
    enableTelemetry: true
  }
}

output id string = search.outputs.resourceId
output name string = search.outputs.name
```

### Tests

A module call compiles to a nested deployment whose `properties.parameters.<param>.value` is
the decision, so every decision above is observable in `tests/*.armtest.yaml`
([bicep-idiom.md](../../../core/iac-rendering/references/bicep-idiom.md#tests)).

## Authored rendering

The fallback. `Microsoft.Search/searchServices` with `properties`:

| Decision | Property |
|---|---|
| `sku` | `sku.name` |
| `replica_count`, `partition_count` | `properties.replicaCount`, `properties.partitionCount` |
| `semantic_ranker` | `properties.semanticSearch` |
| `public_network_access` | `properties.publicNetworkAccess`, `networkRuleSet.ipRules`, `networkRuleSet.bypass` |
| `local_authentication_disabled` | `properties.disableLocalAuth` |
| `cmk_enforcement` | `properties.encryptionWithCmk.enforcement` |
| `managed_identity` | `identity.type` |
