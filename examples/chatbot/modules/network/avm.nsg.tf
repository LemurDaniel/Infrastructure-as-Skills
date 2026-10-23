data "naming_name" "nsg" {
  for_each = local.nsg_purpose

  resource   = "Azure::Microsoft.Network/networkSecurityGroups"
  parameters = { name = "${var.workload}${each.key}" }
}

module "nsg" {
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "~> 0.6.0"

  for_each = local.nsg_purpose

  name      = data.naming_name.nsg[each.key].name
  location  = var.location
  parent_id = var.resource_group_id

  security_rules = merge(
    {
      # decision: network-security-group.rules.default_inbound - explicit, so it is in the plan
      deny_all_inbound = {
        name                       = "deny-all-inbound"
        priority                   = 4096
        direction                  = "Inbound"
        access                     = "Deny"
        protocol                   = "*"
        source_address_prefix      = "*"
        source_port_range          = "*"
        destination_address_prefix = "*"
        destination_port_range     = "*"
      }
    },
    local.nsg_baseline[each.key],
  )

  diagnostic_settings = {
    workspace = {
      workspace_resource_id = var.workspace_resource_id
      logs = [
        { category = "NetworkSecurityGroupEvent" },
        { category = "NetworkSecurityGroupRuleCounter" },
      ]
    }
  }

  enable_telemetry = true
  tags             = var.tags
}
