# The production stage, rendered from ../infra-spec.yaml: context: and every per-stage
# value for `production`. development and test get their own files once their
# subscriptions, groups and platform parts are answered (spec: open). One state per
# stage: terraform init -backend-config="key=invoicing/production.tfstate".
environment         = "production"
location            = "westeurope"
workload            = "invoicing"
subscription_id     = "11111111-2222-3333-4444-555555555555"
resource_group_name = "rg-invoicing-prod-we"

vnet_name                     = "vnet-hub-prod-we"
network_resource_group_name   = "rg-network-prod-we"
private_endpoint_subnet_name  = "snet-privatelink"
workspace_name                = "log-platform-prod-we"
workspace_resource_group_name = "rg-observability-prod-we"

# Production keeps the derived replication; the non-production stages' files carry LRS.
replication = "ZRS"
