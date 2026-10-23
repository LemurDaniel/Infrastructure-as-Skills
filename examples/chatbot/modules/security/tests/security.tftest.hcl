# security: plan-only, run with `terraform -chdir=modules/security test`. The family module is the
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
  tenant_id             = "99999999-8888-7777-6666-555555555555"
  workspace_resource_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.OperationalInsights/workspaces/log-we-prod-chatbot-01"
  subnet_ids = {
    "snet-endpoints" = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.Network/virtualNetworks/vnet-we-prod-chatbot-01/subnets/snet-endpoints"
    "snet-web"       = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.Network/virtualNetworks/vnet-we-prod-chatbot-01/subnets/snet-web"
    "snet-mcp"       = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.Network/virtualNetworks/vnet-we-prod-chatbot-01/subnets/snet-mcp"
    "snet-func"      = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.Network/virtualNetworks/vnet-we-prod-chatbot-01/subnets/snet-func"
    "snet-aca"       = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we/providers/Microsoft.Network/virtualNetworks/vnet-we-prod-chatbot-01/subnets/snet-aca"
  }
  role_assignments_uai = {}
  secret_placeholders  = []
}

# --- identity ---
run "identity" {
  command = plan

  # not-testable: key-vault.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read
}

# --- naming ---
run "naming" {
  command = plan

  assert {
    condition     = data.naming_name.key_vault.name == "kv-prod-chatbot-128f"
    error_message = "The key vault name must come from naming.yaml: kv-prod-chatbot-128f, got ${data.naming_name.key_vault.name}."
  }

  assert {
    condition     = data.naming_name.private_endpoint["kv"].name == "pep-we-prod-chatbotkv-vault-01"
    error_message = "The key vault private endpoint name must come from naming.yaml: pep-we-prod-chatbotkv-vault-01, got ${data.naming_name.private_endpoint["kv"].name}."
  }
}

# --- networking ---
run "networking" {
  command = plan

  # not-testable: key-vault.networking.public_network_access - the key-vault module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: key-vault.networking.private_endpoint_subnet - the private endpoint is a child resource of the module; the root sees only its name

  # not-testable: key-vault.networking.network_acl_bypass - the key-vault module exposes no attribute for it; set through the module input, reviewed in the call
}

# --- observability ---
run "observability" {
  command = plan

  # not-testable: key-vault.observability.diagnostic_workspace - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: key-vault.observability.diagnostic_categories - the diagnostic setting is built by the module in a child resource, which the root cannot read

  # not-testable: key-vault.observability.metrics_enabled - the diagnostic setting is built by the module in a child resource, which the root cannot read
}

# --- security ---
run "security" {
  command = plan

  # not-testable: key-vault.security.enabled_for_services - the key-vault module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: key-vault.security.secret_placeholders - the key-vault module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: key-vault.vault.sku - the key-vault module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: key-vault.vault.purge_protection - the key-vault module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: key-vault.vault.soft_delete_retention_days - the key-vault module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: key-vault.vault.rbac_authorization - the key-vault module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: key-vault.keys.key_management - platform-managed keys: the module is given no key, nothing to observe
}
