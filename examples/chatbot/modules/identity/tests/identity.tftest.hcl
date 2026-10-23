# identity: plan-only, run with `terraform -chdir=modules/identity test`. The family module is the
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
  location            = "westeurope"
  workload            = "chatbot"
  resource_group_name = "rg-chatbot-prod-we"
  resource_group_id   = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we"
  tags                = {}
}

# --- identity ---
run "identity" {
  command = plan

  # decision: user-assigned-identity__web.identity.purpose
  assert {
    condition     = module.identity["web"].resource.tags["purpose"] == "the web app and the MCP server, to reach models, search, data and secrets"
    error_message = "user-assigned-identity__web.identity.purpose must be \"the web app and the MCP server, to reach models, search, data and secrets\", got ${try(jsonencode(module.identity["web"].resource.tags["purpose"]), "unknown")}."
  }

  # not-testable: user-assigned-identity__web.identity.federated_credentials - the module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: user-assigned-identity__web.identity.isolation_scope - the module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: user-assigned-identity__web.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read

  # decision: user-assigned-identity__connector.identity.purpose
  assert {
    condition     = module.identity["connector"].resource.tags["purpose"] == "the document connector function, to index documents and keep its own state"
    error_message = "user-assigned-identity__connector.identity.purpose must be \"the document connector function, to index documents and keep its own state\", got ${try(jsonencode(module.identity["connector"].resource.tags["purpose"]), "unknown")}."
  }

  # not-testable: user-assigned-identity__connector.identity.federated_credentials - the module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: user-assigned-identity__connector.identity.isolation_scope - the module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: user-assigned-identity__connector.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read

  # decision: user-assigned-identity__runner.identity.purpose
  assert {
    condition     = module.identity["runner"].resource.tags["purpose"] == "the code interpreter container app, to pull its image"
    error_message = "user-assigned-identity__runner.identity.purpose must be \"the code interpreter container app, to pull its image\", got ${try(jsonencode(module.identity["runner"].resource.tags["purpose"]), "unknown")}."
  }

  # not-testable: user-assigned-identity__runner.identity.federated_credentials - the module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: user-assigned-identity__runner.identity.isolation_scope - the module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: user-assigned-identity__runner.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read
}
