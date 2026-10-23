# The workload's own spoke network (deployment.network_ownership: create) and the network
# security groups guarding its subnets. The hub, the peering to it and the private DNS zones
# are the platform's (landing_zone: corp) and are not rendered here.

locals {
  # What each subnet is delegated to (virtual-network.subnet_policy.subnet_delegations): the
  # App Service plans integrate through snet-web and snet-mcp, the function app (Flex
  # Consumption) and the Container Apps environment through snet-func and snet-aca. A
  # delegated subnet is exclusive to one plan or environment.
  delegations = {
    "snet-web"  = "Microsoft.Web/serverFarms"
    "snet-mcp"  = "Microsoft.Web/serverFarms"
    "snet-func" = "Microsoft.App/environments"
    "snet-aca"  = "Microsoft.App/environments"
  }

  # Which NSG guards which subnet (virtual-network.security.subnets_expecting_nsg). One group
  # per purpose, attached to every subnet of that purpose.
  subnet_nsg = {
    "snet-endpoints" = "endpoints"
    "snet-web"       = "integration"
    "snet-mcp"       = "integration"
    "snet-func"      = "integration"
    "snet-aca"       = "containerapps"
  }

  # The explicit baseline per subnet purpose (network-security-group.rules.subnet_purpose);
  # see resources/network/network-security-group/notes.md. The deny at 4096 overrides
  # Azure's built-in allow-everything-from-the-virtual-network, so each legitimate flow is a
  # rule a reviewer can read.
  nsg_purpose = {
    endpoints     = "private_endpoints"
    integration   = "app_integration"
    containerapps = "container_apps"
  }

  nsg_baseline = {
    # Only traffic to the services behind the endpoints, on 443, from inside the network.
    endpoints = {
      allow_vnet_https_inbound = {
        name                       = "allow-vnet-https-inbound"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_address_prefix      = "VirtualNetwork"
        source_port_range          = "*"
        destination_address_prefix = "VirtualNetwork"
        destination_port_range     = "443"
      }
      # decision: network-security-group.rules.default_outbound - nothing leaves this subnet
      deny_internet_outbound = {
        name                       = "deny-internet-outbound"
        priority                   = 4096
        direction                  = "Outbound"
        access                     = "Deny"
        protocol                   = "*"
        source_address_prefix      = "*"
        source_port_range          = "*"
        destination_address_prefix = "Internet"
        destination_port_range     = "*"
      }
    }
    # Outbound integration only: nothing is called in, so nothing is allowed in.
    integration = {}
    # The apps in the environment are called from the integration subnets, on 80 and 443.
    containerapps = {
      allow_vnet_http_inbound = {
        name                       = "allow-vnet-http-inbound"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_address_prefix      = "VirtualNetwork"
        source_port_range          = "*"
        destination_address_prefix = "*"
        destination_port_ranges    = ["80", "443"]
      }
    }
  }
}

data "naming_name" "network" {
  resource = "Azure::Microsoft.Network/virtualNetworks"
}

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
  parent_id = data.azurerm_resource_group.this.id

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
      workspace_resource_id = module.workspace.resource_id
      logs = [
        { category = "NetworkSecurityGroupEvent" },
        { category = "NetworkSecurityGroupRuleCounter" },
      ]
    }
  }

  enable_telemetry = true
  tags             = local.tags
}

module "network" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.22.0"

  name      = data.naming_name.network.name
  location  = var.location
  parent_id = data.azurerm_resource_group.this.id

  # decision: virtual-network.addressing.address_space
  address_space = [var.address_space]

  # decision: virtual-network.addressing.subnets
  subnets = {
    for name, s in var.subnets : name => {
      name             = name
      address_prefixes = [s.prefix]
      # decision: virtual-network.subnet_policy.private_endpoint_network_policies - Enabled,
      # so the subnet's NSG applies to private endpoint traffic
      private_endpoint_network_policies = "Enabled"
      service_endpoints                 = []
      # decision: virtual-network.subnet_policy.subnet_delegations
      delegations = contains(keys(local.delegations), name) ? [{
        name               = "delegation"
        service_delegation = { name = local.delegations[name] }
      }] : []
      # decision: virtual-network.security.subnets_expecting_nsg
      network_security_group = { id = module.nsg[local.subnet_nsg[name]].resource_id }
    }
  }

  diagnostic_settings = {
    workspace = {
      workspace_resource_id = module.workspace.resource_id
      metrics               = [{ category = "AllMetrics" }]
    }
  }

  enable_telemetry = true
  tags             = local.tags
}
