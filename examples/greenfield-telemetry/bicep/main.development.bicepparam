// The development stage, rendered from ../infra-spec.yaml. PLACEHOLDERS: values marked OPEN-...
// are unanswered in the spec (open: entries owned by the network / IPAM owner and the
// platform team) - this stage cannot deploy until they are real; the pipeline refuses it.
//   deployment.address_space, deployment.private_endpoint_subnet_prefix,
//   resources.virtual-network.addressing.*, context.subscription_id,
//   context.resource_group_name (the last two are the deployment scope: the pipeline's
//   variable group iac-telemetry-development carries them)
using 'main.bicep'

param environment = 'development'
param location = 'germanywestcentral'
param workload = 'telemetry'

param addressSpace = 'OPEN-address-space'
param subnets = [
  { name: 'OPEN-privatelink-subnet', addressPrefix: 'OPEN-privatelink-prefix' }
  { name: 'snet-app', addressPrefix: 'OPEN-app-prefix' }
]

// non_production_savings: enabled - cheaper replication. The retention was stated, so it holds in every stage.
param storageSkuName = 'Standard_LRS'
param logRetentionDays = 90
