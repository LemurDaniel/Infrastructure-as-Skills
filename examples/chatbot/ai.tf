data "naming_name" "foundry" {
  resource   = "Azure::Microsoft.CognitiveServices/accounts::AIServices"
  parameters = { name = "${var.workload}foundry" }
}

# The account is AI Foundry (kind AIServices): the chat and embedding models, and the project
# the application works in. The module is AzAPI-based but constrains azurerm < 5.0 as well.
module "foundry" {
  source  = "Azure/avm-res-cognitiveservices-account/azurerm"
  version = "~> 0.11.0"

  name      = data.naming_name.foundry.name
  location  = var.location
  parent_id = data.azurerm_resource_group.this.id

  # decision: foundry.account.kind / sku_name
  kind     = "AIServices"
  sku_name = "S0"
  # The hostname: required for the firewall, private endpoints and token authentication.
  custom_subdomain_name = data.naming_name.foundry.name

  # decision: foundry.account.project_management
  allow_project_management = true

  # decision: foundry.models.* - one entry per deployment; the model and the version are
  # pinned, never left to a default. DataZoneStandard keeps processing inside the EU data
  # zone (deployment.mandates), where the portal's own default would process anywhere.
  cognitive_deployments = {
    chat = {
      name = "chat"
      model = {
        format  = "OpenAI"
        name    = "gpt-4.1"
        version = "2025-04-14"
      }
      scale = {
        type     = "DataZoneStandard"
        capacity = 10
      }
      # decision: foundry.models.version_upgrade_option - the module default moves on
      # Microsoft's schedule
      version_upgrade_option = "OnceCurrentVersionExpired"
      # decision: foundry.models.content_filter
      rai_policy_name = "Microsoft.DefaultV2"
    }
    embeddings = {
      name = "embeddings"
      model = {
        format  = "OpenAI"
        name    = "text-embedding-3-large"
        version = "1"
      }
      scale = {
        type     = "DataZoneStandard"
        capacity = 10
      }
      version_upgrade_option = "OnceCurrentVersionExpired"
      rai_policy_name        = "Microsoft.DefaultV2"
    }
  }

  # decision: foundry.networking.public_network_access - a bool, module default true
  public_network_access_enabled = false
  # decision: foundry.networking.restrict_outbound - the module default is off
  outbound_network_access_restricted = true
  private_endpoints = {
    account = {
      name               = data.naming_name.private_endpoint["foundry"].name
      subnet_resource_id = module.network.subnets["snet-endpoints"].resource_id
    }
  }
  # deployment.private_dns_records: policy - the platform policy writes the record
  private_endpoints_manage_dns_zone_group = false

  # decision: foundry.identity.managed_identity
  managed_identities = { system_assigned = true }

  # decision: foundry.security.local_authentication_disabled - an inverse input
  local_auth_enabled = false

  role_assignments = merge(
    lookup(local.role_assignments_uai, "foundry", {}),
    lookup(local.role_assignments_search, "foundry", {}),
  )

  diagnostic_settings = {
    workspace = {
      workspace_resource_id = module.workspace.resource_id
      logs = [
        { category = "Audit" },
        { category = "RequestResponse" },
        { category = "AzureOpenAIRequestUsage" },
      ]
      metrics = [{ category = "AllMetrics" }]
    }
  }

  enable_telemetry = true
  tags             = local.tags
}

# decision: foundry.account.projects - neither AVM module creates a project, so it is a
# child resource next to the module, with its own identity.
resource "azapi_resource" "foundry_project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name      = "chatbot"
  parent_id = module.foundry.resource_id
  location  = var.location

  body = {
    identity   = { type = "SystemAssigned" }
    properties = {}
  }
}

data "naming_name" "search" {
  resource   = "Azure::Microsoft.Search/searchServices"
  parameters = { name = "${var.workload}search" }
}

module "search" {
  source  = "Azure/avm-res-search-searchservice/azurerm"
  version = "~> 0.3.0"

  name                = data.naming_name.search.name
  location            = var.location
  resource_group_name = var.resource_group_name

  # decision: search-service.service.sku
  sku = "standard"
  # decision: search-service.service.replica_count - derived from outage_impact; the module
  # default is 1 (Bicep's is 3)
  replica_count = 2
  # decision: search-service.service.partition_count
  partition_count = 1
  # decision: search-service.service.semantic_ranker
  semantic_search_sku = "free"

  # decision: search-service.networking.public_network_access - a bool, module default true
  public_network_access_enabled = false
  # decision: search-service.networking.network_rule_bypass
  network_rule_bypass_option = "None"
  private_endpoints = {
    search = {
      name               = data.naming_name.private_endpoint["search"].name
      subnet_resource_id = module.network.subnets["snet-endpoints"].resource_id
    }
  }
  # deployment.private_dns_records: policy - the platform policy writes the record
  private_endpoints_manage_dns_zone_group = false

  # decision: search-service.identity.managed_identity
  managed_identities = { system_assigned = true }

  # decision: search-service.security.local_authentication_disabled - an inverse input; the
  # module leaves keys on
  local_authentication_enabled = false

  role_assignments = lookup(local.role_assignments_uai, "search-service", {})

  diagnostic_settings = {
    workspace = {
      workspace_resource_id = module.workspace.resource_id
      logs                  = [{ category = "OperationLogs" }]
      metrics               = [{ category = "AllMetrics" }]
    }
  }

  enable_telemetry = true
  tags             = local.tags
}
