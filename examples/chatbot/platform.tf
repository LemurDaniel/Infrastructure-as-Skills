# Platform infrastructure this deployment references and never manages. In this
# deployment that is the resource group and the tenant: the network is created here
# (network_ownership: create), the workspace is created here (observability_ownership:
# create), and the hub, the peering and the privatelink DNS zones belong to the platform
# (landing_zone: corp, private_dns_ownership: platform, private_dns_records: policy) -
# the platform's DeployIfNotExists policy writes the records, so nothing here does.

# The AzAPI-based modules take the resource group as parent_id - an id, not a name.
data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

data "azurerm_client_config" "this" {}
