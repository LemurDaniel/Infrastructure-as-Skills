# The development stage, rendered from ../infra-spec.yaml. PLACEHOLDERS: the values below
# marked 00000000-... / OPEN-... are unanswered in the spec (open: entries owned by the
# platform team) - this stage cannot deploy until they are real; the pipeline refuses it.
#   context.subscription_id, context.resource_group_name,
#   deployment.existing_vnet, deployment.private_endpoint_subnet,
#   deployment.diagnostics_destination
# One state per stage: terraform init -backend-config="key=invoicing/development.tfstate".
environment         = "development"
location            = "westeurope"
workload            = "invoicing"
subscription_id     = "00000000-0000-0000-0000-000000000000"
resource_group_name = "OPEN-resource-group"

vnet_name                     = "OPEN-hub-vnet"
network_resource_group_name   = "OPEN-network-resource-group"
private_endpoint_subnet_name  = "OPEN-privatelink-subnet"
workspace_name                = "OPEN-workspace"
workspace_resource_group_name = "OPEN-workspace-resource-group"

# non_production_savings: enabled - known without the open items.
replication = "LRS"
