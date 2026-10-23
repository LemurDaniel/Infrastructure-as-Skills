# ai: plan-only, run with `terraform -chdir=modules/ai test`. The family module is the
# unit under test, so an assert reads the AVM module by its own name (module.foundry) and the
# rendered names from the data sources beside it. Mocks and variables repeat in every file of
# tests/ - terraform test has no include.

mock_provider "azurerm" {
}

mock_provider "azapi" {
  # The Flex plan module asks which regions advertise zone-redundant Flex Consumption.
  mock_data "azapi_resource_action" {
    defaults = {
      output = {
        value = [{ properties = { name = "West Europe", orgDomain = "FCZONEREDUNDANCY" } }]
      }
    }
  }
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id          = "11111111-2222-3333-4444-555555555555"
      subscription_resource_id = "/subscriptions/11111111-2222-3333-4444-555555555555"
      tenant_id                = "99999999-8888-7777-6666-555555555555"
    }
  }
}

mock_provider "modtm" {
}

# The naming provider stays real, so rendered names are asserted as they will be deployed.
# The seed is the root's: <subscription_id>/<resource_group_name>.
provider "naming" {
  convention  = "default"
  naming      = "../../naming.yaml"
  random_seed = "11111111-2222-3333-4444-555555555555/rg-chatbot-prod-we"

  parameters = {
    location    = "westeurope"
    environment = "production"
    name        = "chatbot"
  }
}

variables {
  location              = "westeurope"
  workload              = "chatbot"
  resource_group_name   = "rg-chatbot-prod-we"
  resource_group_id     = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we"
  tags                  = {}
  workspace_resource_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.OperationalInsights/workspaces/log-we-prod-chatbot-01"
  subnet_ids = {
    "snet-endpoints" = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.Network/virtualNetworks/vnet-we-prod-chatbot-01/subnets/snet-endpoints"
    "snet-web"       = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.Network/virtualNetworks/vnet-we-prod-chatbot-01/subnets/snet-web"
    "snet-mcp"       = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.Network/virtualNetworks/vnet-we-prod-chatbot-01/subnets/snet-mcp"
    "snet-func"      = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.Network/virtualNetworks/vnet-we-prod-chatbot-01/subnets/snet-func"
    "snet-aca"       = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.Network/virtualNetworks/vnet-we-prod-chatbot-01/subnets/snet-aca"
  }
  role_assignments_uai = {}
  role_assignments     = {}
}

# --- compute ---
run "compute" {
  command = plan

  # not-testable: foundry.account.kind - the module resource output carries no kind or project-management attribute for the AIServices form

  # decision: foundry.account.sku_name
  assert {
    condition     = module.foundry.resource.sku_name == "S0"
    error_message = "foundry.account.sku_name must be \"S0\", got ${try(jsonencode(module.foundry.resource.sku_name), "unknown")}."
  }

  # not-testable: foundry.account.project_management - the module resource output carries no kind or project-management attribute for the AIServices form

  # not-testable: foundry.account.projects - the project is a separate azapi_resource beside the module; its name is its address

  # decision: search-service.service.sku
  assert {
    condition     = module.search.resource.sku == "standard"
    error_message = "search-service.service.sku must be \"standard\", got ${try(jsonencode(module.search.resource.sku), "unknown")}."
  }

  # decision: search-service.service.replica_count
  assert {
    condition     = module.search.resource.replica_count == 2
    error_message = "search-service.service.replica_count must be 2, got ${try(jsonencode(module.search.resource.replica_count), "unknown")}."
  }

  # decision: search-service.service.partition_count
  assert {
    condition     = module.search.resource.partition_count == 1
    error_message = "search-service.service.partition_count must be 1, got ${try(jsonencode(module.search.resource.partition_count), "unknown")}."
  }

  # decision: search-service.service.semantic_ranker
  assert {
    condition     = module.search.resource.semantic_search_sku == "free"
    error_message = "search-service.service.semantic_ranker must be \"free\", got ${try(jsonencode(module.search.resource.semantic_search_sku), "unknown")}."
  }
}

# --- data_protection ---
run "data_protection" {
  command = plan

  # not-testable: foundry.models.model_deployments - model deployments are child resources of the module, which the root cannot read

  # not-testable: foundry.models.deployment_sku - model deployments are child resources of the module, which the root cannot read

  # not-testable: foundry.models.deployment_capacity - model deployments are child resources of the module, which the root cannot read

  # not-testable: foundry.models.version_upgrade_option - model deployments are child resources of the module, which the root cannot read

  # not-testable: foundry.models.content_filter - model deployments are child resources of the module, which the root cannot read
}

# --- identity ---
run "identity" {
  command = plan

  # not-testable: foundry.identity.managed_identity - the module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: foundry.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read

  # decision: search-service.identity.managed_identity
  assert {
    condition     = module.search.resource.identity[0].type == "SystemAssigned"
    error_message = "search-service.identity.managed_identity must be \"SystemAssigned\", got ${try(jsonencode(module.search.resource.identity[0].type), "unknown")}."
  }

  # not-testable: search-service.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read
}

# --- networking ---
run "networking" {
  command = plan

  # decision: foundry.networking.public_network_access
  assert {
    condition     = module.foundry.resource.public_network_access == "Disabled"
    error_message = "foundry.networking.public_network_access must be \"Disabled\", got ${try(jsonencode(module.foundry.resource.public_network_access), "unknown")}."
  }

  # not-testable: foundry.networking.private_endpoint_subnet - the private endpoint is a child resource of the module; the root sees only its name

  # decision: foundry.networking.restrict_outbound
  assert {
    condition     = module.foundry.resource.outbound_network_access_restricted == true
    error_message = "foundry.networking.restrict_outbound must be true, got ${try(jsonencode(module.foundry.resource.outbound_network_access_restricted), "unknown")}."
  }

  # decision: search-service.networking.public_network_access
  assert {
    condition     = module.search.resource.public_network_access_enabled == false
    error_message = "search-service.networking.public_network_access must be false, got ${try(jsonencode(module.search.resource.public_network_access_enabled), "unknown")}."
  }

  # not-testable: search-service.networking.private_endpoint_subnet - the private endpoint is a child resource of the module; the root sees only its name

  # decision: search-service.networking.network_rule_bypass
  assert {
    condition     = module.search.resource.network_rule_bypass_option == "None"
    error_message = "search-service.networking.network_rule_bypass must be \"None\", got ${try(jsonencode(module.search.resource.network_rule_bypass_option), "unknown")}."
  }
}

# --- observability ---
run "observability" {
  command = plan

  # not-testable: foundry.observability.diagnostic_workspace - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: foundry.observability.diagnostic_categories - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: foundry.observability.metrics_enabled - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: search-service.observability.diagnostic_workspace - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: search-service.observability.diagnostic_categories - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: search-service.observability.metrics_enabled - the diagnostic setting is built by the module in a child resource, which the root cannot read
}

# --- security ---
run "security" {
  command = plan

  # decision: foundry.security.local_authentication_disabled
  assert {
    condition     = tostring(module.foundry.resource.local_authentication_enabled) == "false"
    error_message = "foundry.security.local_authentication_disabled must be \"false\", got ${try(jsonencode(tostring(module.foundry.resource.local_authentication_enabled)), "unknown")}."
  }

  # not-testable: foundry.security.key_management - platform-managed keys: the module is given no key, nothing to observe

  # decision: search-service.security.local_authentication_disabled
  assert {
    condition     = tostring(module.search.resource.local_authentication_enabled) == "false"
    error_message = "search-service.security.local_authentication_disabled must be \"false\", got ${try(jsonencode(tostring(module.search.resource.local_authentication_enabled)), "unknown")}."
  }

  # not-testable: search-service.security.key_management - platform-managed keys: the module is given no key, nothing to observe
}
