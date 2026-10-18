// The staging stage, rendered from ../infra-spec.yaml: context: and every per-stage value
// for `staging`. The subscription (aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee) and the resource
// group (rg-telemetry-stg-gwc) are the deployment's scope, given on the command line -
// one subscription per stage (deployment.stage_isolation: subscription):
//   az deployment group what-if --subscription <id> --resource-group rg-telemetry-stg-gwc --template-file main.bicep --parameters main.staging.bicepparam
// development, test and production get their own files once their ranges, subscriptions
// and groups are answered (spec: open).
using 'main.bicep'

param environment = 'staging'
param location = 'germanywestcentral'
param workload = 'telemetry'

// deployment.address_space / virtual-network.addressing.subnets - staging's, as stated
param addressSpace = '10.20.0.0/16'
param subnets = [
  { name: 'snet-stg-privatelink-01', addressPrefix: '10.20.1.0/27' }
  { name: 'snet-app', addressPrefix: '10.20.2.0/24' }
]

// Non-production stage with non_production_savings enabled: cheaper replication and
// the default retention; production's file carries Standard_ZRS and 90.
param storageSkuName = 'Standard_LRS'
param logRetentionDays = 30
