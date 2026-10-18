// Rendered from ../infra-spec.yaml context: - the stated values. The subscription
// (aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee) and the resource group (rg-telemetry-stg-gwc)
// are the deployment's scope, given on the command line:
//   az deployment group what-if --subscription <id> --resource-group rg-telemetry-stg-gwc --template-file main.bicep --parameters main.bicepparam
using 'main.bicep'

param environment = 'staging'
param location = 'germanywestcentral'
param workload = 'telemetry'
