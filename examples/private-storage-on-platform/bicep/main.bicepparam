// Rendered from ../infra-spec.yaml context: and deployment: - the stated values.
// The subscription (11111111-2222-3333-4444-555555555555) and the resource group
// (rg-invoicing-prod-we) are the deployment's scope, given on the command line:
//   az deployment group what-if --subscription <id> --resource-group rg-invoicing-prod-we --template-file main.bicep --parameters main.bicepparam
using 'main.bicep'

param environment = 'production'
param location = 'westeurope'
param workload = 'invoicing'

param vnetName = 'vnet-hub-prod-we'
param networkResourceGroupName = 'rg-network-prod-we'
param privateEndpointSubnetName = 'snet-privatelink'
param workspaceName = 'log-platform-prod-we'
param workspaceResourceGroupName = 'rg-observability-prod-we'
