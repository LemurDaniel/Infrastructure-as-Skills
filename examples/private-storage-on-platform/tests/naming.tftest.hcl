# Plan-only, so it needs no credentials. The platform is referenced through data
# sources, which a real plan would have to read from Azure - the mock provider
# answers them with placeholder values instead. The AVM module plans against a
# mocked azapi and modtm the same way; the naming provider stays real, so
# rendered names are asserted as they will be deployed.
#
# Every decision under resources: in ../infra-spec.yaml is asserted exactly once,
# named by its key path in a `# decision:` comment; what a plan cannot observe is
# marked `# not-testable:` with its reason. check_render_coverage.py checks both.
#
# With a module in the middle the assert target is the module's `resource` output:
# the azapi_resource the module creates, whose `body` is what this root passed in
# and is known at plan time. Sub-resources the module creates in its own child
# modules (blob service, diagnostic settings, role assignments) are not reachable
# from a test of the root - those decisions lean on the module's own tests.
mock_provider "azurerm" {
  # The provider validates every referenced id's shape, so the mocked data
  # sources need ids that parse - a random placeholder string does not.
  mock_data "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-invoicing-prod-we"
    }
  }
  mock_data "azurerm_virtual_network" {
    defaults = {
      id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-network-prod-we/providers/Microsoft.Network/virtualNetworks/vnet-hub-prod-we"
    }
  }
  mock_data "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-network-prod-we/providers/Microsoft.Network/virtualNetworks/vnet-hub-prod-we/subnets/snet-privatelink"
    }
  }
  mock_data "azurerm_log_analytics_workspace" {
    defaults = {
      id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-observability-prod-we/providers/Microsoft.OperationalInsights/workspaces/log-platform-prod-we"
    }
  }
}

mock_provider "azapi" {}
mock_provider "modtm" {}

variables {
  environment         = "production"
  location            = "westeurope"
  workload            = "invoicing"
  subscription_id     = "11111111-2222-3333-4444-555555555555"
  resource_group_name = "rg-invoicing-prod-we"

  vnet_name                     = "vnet-hub-prod-we"
  network_resource_group_name   = "rg-network-prod-we"
  private_endpoint_subnet_name  = "snet-privatelink"
  workspace_name                = "log-platform-prod-we"
  workspace_resource_group_name = "rg-observability-prod-we"
  replication                   = "ZRS"
}

run "naming" {
  command = plan

  assert {
    condition     = module.storage.resource.name == "stweprodinvoicing01"
    error_message = "Storage account name must come from naming.yaml: stweprodinvoicing01."
  }

  assert {
    condition     = module.storage.private_endpoints["blob"].name == "pep-we-prod-invoicing-blob-01"
    error_message = "Private endpoint name must come from naming.yaml, <?SUBNAME> before the index."
  }

  # The module takes the group as an id, not a name - the wrong one is a silent misplacement.
  assert {
    condition     = module.storage.resource.parent_id == data.azurerm_resource_group.this.id
    error_message = "The account is placed into the context's resource group."
  }
}

# A non-production stage renders from the same code with its own file: the name
# carries the stage, and the savings knob lands in the SKU.
run "non_production_stage" {
  command = plan

  variables {
    environment         = "development"
    replication         = "LRS"
    resource_group_name = "rg-invoicing-dev-we"
  }

  assert {
    condition     = module.storage.resource.name == "stwedevinvoicing01"
    error_message = "The development stage's name carries its environment code."
  }

  assert {
    condition     = module.storage.resource.body.sku.name == "Standard_LRS"
    error_message = "non_production_savings: the development stage runs on LRS."
  }
}
