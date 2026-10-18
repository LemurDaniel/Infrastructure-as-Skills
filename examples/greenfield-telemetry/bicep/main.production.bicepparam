// The production stage, rendered from ../infra-spec.yaml. PLACEHOLDERS: values marked OPEN-...
// are unanswered in the spec (open: entries owned by the network / IPAM owner and the
// platform team) - this stage cannot deploy until they are real; the pipeline refuses it.
//   deployment.address_space, deployment.private_endpoint_subnet_prefix,
//   resources.virtual-network.addressing.*, context.subscription_id,
//   context.resource_group_name (the last two are the deployment scope: the pipeline's
//   variable group iac-telemetry-production carries them)
using 'main.bicep'

param environment = 'production'
param location = 'germanywestcentral'
param workload = 'telemetry'

param addressSpace = 'OPEN-address-space'
param subnets = [
  { name: 'OPEN-privatelink-subnet', addressPrefix: 'OPEN-privatelink-prefix' }
  { name: 'snet-app', addressPrefix: 'OPEN-app-prefix' }
]

// production keeps the derived replication (ZRS). The retention was stated, so it holds in every stage.
param storageSkuName = 'Standard_ZRS'
param logRetentionDays = 90
