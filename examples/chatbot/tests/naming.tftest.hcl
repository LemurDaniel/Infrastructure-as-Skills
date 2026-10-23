# Plan-only, so it needs no credentials. The platform is referenced through data sources and
# the AVM modules plan against mocked azurerm, azapi and modtm providers; the naming provider
# stays real, so rendered names are asserted as they will be deployed.
#
# Every decision under resources: in ../infra-spec.yaml is asserted exactly once, named by its
# key path in a `# decision:` comment; what a plan cannot observe is marked `# not-testable:`
# with its reason. check_render_coverage.py checks both. With a module in the middle the assert
# target is the module's `resource` output (azapi-based modules: its `body`; azurerm-based
# ones: the attributes it echoes), or another of its outputs. What a module builds in child
# resources - private endpoints, role assignments, diagnostic settings, sub-resources - is not
# reachable from a test of the root.
#
# Two things the tests do not and cannot cover, both findings of this example:
#   - avm-res-app-managedenvironment declares an ephemeral resource in every version, which
#     mock providers cannot plan, so the environment is rendered authored (azapi_resource);
#   - avm-res-keyvault-vault and avm-res-containerregistry-registry expose no attribute at
#     all, so their decisions are reviewed in the call and marked not-testable.

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

run "naming" {
  command = plan

  assert {
    condition     = data.naming_name.network.name == "vnet-we-prod-chatbot-01"
    error_message = "The network name must come from naming.yaml: vnet-we-prod-chatbot-01, got ${data.naming_name.network.name}."
  }

  assert {
    condition     = data.naming_name.storage_account["uploads"].name == "stweprodchatbotuploads01"
    error_message = "The storage account for uploads name must come from naming.yaml: stweprodchatbotuploads01, got ${data.naming_name.storage_account["uploads"].name}."
  }

  assert {
    condition     = data.naming_name.storage_account["host"].name == "stweprodchatbothost01"
    error_message = "The storage account for the host name must come from naming.yaml: stweprodchatbothost01, got ${data.naming_name.storage_account["host"].name}."
  }

  assert {
    condition     = data.naming_name.key_vault.name == "kv-prod-chatbot-128f"
    error_message = "The key vault name must come from naming.yaml: kv-prod-chatbot-128f, got ${data.naming_name.key_vault.name}."
  }

  assert {
    condition     = data.naming_name.registry.name == "crweprodchatbot01"
    error_message = "The registry name must come from naming.yaml: crweprodchatbot01, got ${data.naming_name.registry.name}."
  }

  assert {
    condition     = data.naming_name.app["web"].name == "app-we-prod-chatbotweb-01"
    error_message = "The web app name must come from naming.yaml: app-we-prod-chatbotweb-01, got ${data.naming_name.app["web"].name}."
  }

  assert {
    condition     = data.naming_name.function.name == "func-we-prod-chatbotfunc-01"
    error_message = "The connector function name must come from naming.yaml: func-we-prod-chatbotfunc-01, got ${data.naming_name.function.name}."
  }

  assert {
    condition     = data.naming_name.private_endpoint["web"].name == "pep-we-prod-chatbotweb-sites-01"
    error_message = "The web app private endpoint name must come from naming.yaml: pep-we-prod-chatbotweb-sites-01, got ${data.naming_name.private_endpoint["web"].name}."
  }

  assert {
    condition     = data.naming_name.private_endpoint["kv"].name == "pep-we-prod-chatbotkv-vault-01"
    error_message = "The key vault private endpoint name must come from naming.yaml: pep-we-prod-chatbotkv-vault-01, got ${data.naming_name.private_endpoint["kv"].name}."
  }

  # The AzAPI-based modules take the group as an id, not a name - the wrong one is a silent misplacement.
  assert {
    condition     = module.storage["uploads"].resource.parent_id == data.azurerm_resource_group.this.id
    error_message = "The storage account is placed into the context's resource group."
  }
}
