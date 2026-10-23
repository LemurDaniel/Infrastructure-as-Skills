# wiring: what only the root can see - the families joined to each other. Every decision is
# asserted inside its family (modules/<family>/tests/); this file plans the whole root, so a
# family output that does not fit the input it feeds, a role map keyed wrongly or a missing
# dependency fails here. Plan-only, platform mocked, naming provider real.

mock_provider "azurerm" {
  mock_data "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we"
    }
  }
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "99999999-8888-7777-6666-555555555555"
    }
  }
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

mock_provider "modtm" {}

variables {
  environment         = "production"
  location            = "westeurope"
  workload            = "chatbot"
  subscription_id     = "11111111-2222-3333-4444-555555555555"
  resource_group_name = "rg-chatbot-prod-we"
  address_space       = "10.20.0.0/16"
  subnets = {
    "snet-endpoints" = { prefix = "10.20.0.0/27" }
    "snet-web"       = { prefix = "10.20.0.64/26" }
    "snet-mcp"       = { prefix = "10.20.0.128/26" }
    "snet-func"      = { prefix = "10.20.0.192/26" }
    "snet-aca"       = { prefix = "10.20.1.0/27" }
  }
  role_assignments = {
    "key-vault"      = [{ principal = "user-assigned-identity__web", role = "Key Vault Secrets User" }]
    "foundry"        = [{ principal = "search-service", role = "Cognitive Services OpenAI User" }]
    "search-service" = [{ principal = "user-assigned-identity__connector", role = "Search Index Data Contributor" }]
  }
}

run "wiring" {
  command = plan

  assert {
    condition     = length(output.identity_ids) == 3 && alltrue([for k in ["web", "connector", "runner"] : contains(keys(output.identity_ids), k)])
    error_message = "The identity family hands out one id per identity: web, connector, runner."
  }
}
