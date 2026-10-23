# Three user-assigned identities, created before the things that use them. The reason to
# use one is the ordering: the apps pull their image and read their storage while they are
# being created, so the identity has to hold its roles first - which an identity created
# with the app cannot.

locals {
  identities = {
    web       = "the web app and the MCP server, to reach models, search, data and secrets"
    connector = "the document connector function, to index documents and keep its own state"
    runner    = "the code interpreter container app, to pull its image"
  }
}

data "naming_name" "identity" {
  for_each = local.identities

  resource   = "Azure::Microsoft.ManagedIdentity/userAssignedIdentities"
  parameters = { name = "${var.workload}${each.key}" }
}

module "identity" {
  source  = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version = "~> 0.5.0"

  for_each = local.identities

  name                = data.naming_name.identity[each.key].name
  location            = var.location
  resource_group_name = var.resource_group_name

  # decision: user-assigned-identity.identity.isolation_scope - None is unset in Terraform
  isolation_scope = null

  enable_telemetry = true
  tags             = merge(local.tags, { purpose = each.value })
}
