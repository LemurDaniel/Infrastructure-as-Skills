# Platform infrastructure this deployment references and never manages
# (network_ownership: reference, observability_ownership: reference). Data
# blocks on purpose: a resource block pointed at someone else's network would
# try to converge it to what this configuration says.

data "azurerm_virtual_network" "platform" {
  name                = var.vnet_name
  resource_group_name = var.network_resource_group_name
}

data "azurerm_subnet" "private_endpoints" {
  name                 = var.private_endpoint_subnet_name
  virtual_network_name = data.azurerm_virtual_network.platform.name
  resource_group_name  = data.azurerm_virtual_network.platform.resource_group_name
}

data "azurerm_log_analytics_workspace" "platform" {
  name                = var.workspace_name
  resource_group_name = var.workspace_resource_group_name
}
