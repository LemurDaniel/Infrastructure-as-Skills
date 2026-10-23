# identity: plan-only, platform mocked, naming provider real. Mocks and variables repeat in every
# file of tests/ - terraform test has no include. The intro comment is in naming.tftest.hcl.

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
}

run "identity" {
  command = plan

  # not-testable: log-analytics-workspace.access.public_network_access - the module exposes no attribute for it; set through the module input, reviewed in the call

  # decision: log-analytics-workspace.access.local_auth
  assert {
    condition     = module.observability.workspace.resource.local_authentication_enabled == false
    error_message = "log-analytics-workspace.access.local_auth must be false, got ${try(jsonencode(module.observability.workspace.resource.local_authentication_enabled), "unknown")}."
  }

  # not-testable: log-analytics-workspace.access.rbac_only_access - the module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: application-insights.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read

  # not-testable: key-vault.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read

  # decision: user-assigned-identity__web.identity.purpose
  assert {
    condition     = module.identity.identities["web"].resource.tags["purpose"] == "the web app and the MCP server, to reach models, search, data and secrets"
    error_message = "user-assigned-identity__web.identity.purpose must be \"the web app and the MCP server, to reach models, search, data and secrets\", got ${try(jsonencode(module.identity.identities["web"].resource.tags["purpose"]), "unknown")}."
  }

  # not-testable: user-assigned-identity__web.identity.federated_credentials - the module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: user-assigned-identity__web.identity.isolation_scope - the module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: user-assigned-identity__web.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read

  # decision: user-assigned-identity__connector.identity.purpose
  assert {
    condition     = module.identity.identities["connector"].resource.tags["purpose"] == "the document connector function, to index documents and keep its own state"
    error_message = "user-assigned-identity__connector.identity.purpose must be \"the document connector function, to index documents and keep its own state\", got ${try(jsonencode(module.identity.identities["connector"].resource.tags["purpose"]), "unknown")}."
  }

  # not-testable: user-assigned-identity__connector.identity.federated_credentials - the module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: user-assigned-identity__connector.identity.isolation_scope - the module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: user-assigned-identity__connector.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read

  # decision: user-assigned-identity__runner.identity.purpose
  assert {
    condition     = module.identity.identities["runner"].resource.tags["purpose"] == "the code interpreter container app, to pull its image"
    error_message = "user-assigned-identity__runner.identity.purpose must be \"the code interpreter container app, to pull its image\", got ${try(jsonencode(module.identity.identities["runner"].resource.tags["purpose"]), "unknown")}."
  }

  # not-testable: user-assigned-identity__runner.identity.federated_credentials - the module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: user-assigned-identity__runner.identity.isolation_scope - the module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: user-assigned-identity__runner.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read

  # not-testable: storage-account__uploads.identity.managed_identity - the identity assignment is a child of the module call; the root cannot read it back

  # not-testable: storage-account__uploads.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read

  # not-testable: storage-account__host.identity.managed_identity - the identity assignment is a child of the module call; the root cannot read it back

  # not-testable: storage-account__host.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read

  # not-testable: cosmos-db.identity.managed_identity - a container- or region-level setting inside the module's nested inputs, not exposed as an output

  # not-testable: cosmos-db.identity.data_plane_role_assignments - the role assignments are child resources of the module, which the root cannot read

  # not-testable: cosmos-db.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read

  # not-testable: foundry.identity.managed_identity - the module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: foundry.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read

  # decision: search-service.identity.managed_identity
  assert {
    condition     = module.ai.search.resource.identity[0].type == "SystemAssigned"
    error_message = "search-service.identity.managed_identity must be \"SystemAssigned\", got ${try(jsonencode(module.ai.search.resource.identity[0].type), "unknown")}."
  }

  # not-testable: search-service.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read

  # not-testable: container-registry.identity.managed_identity - the container-registry module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-registry.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read

  # not-testable: container-apps.identity.managed_identity - the container app module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-apps.identity.user_assigned_identity_ids - the identity assignment is a child of the module call; the root cannot read it back

  # not-testable: container-apps.identity.secret_references - the container app module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: container-apps.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read

  # not-testable: function-app.identity.managed_identity - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: function-app.identity.user_assigned_identity_ids - the identity assignment is a child of the module call; the root cannot read it back

  # not-testable: function-app.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read

  # not-testable: app-service__web.identity.managed_identity - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: app-service__web.identity.user_assigned_identity_ids - the identity assignment is a child of the module call; the root cannot read it back

  # not-testable: app-service__mcp.identity.managed_identity - the site module in this form exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: app-service__mcp.identity.user_assigned_identity_ids - the identity assignment is a child of the module call; the root cannot read it back

}
