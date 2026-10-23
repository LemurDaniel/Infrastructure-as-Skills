# observability: plan-only, run with `terraform -chdir=modules/observability test`. The family module is the
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
  location             = "westeurope"
  workload             = "chatbot"
  resource_group_name  = "rg-chatbot-prod-we"
  resource_group_id    = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-chatbot-prod-we"
  tags                 = {}
  role_assignments_uai = {}
}

# --- compute ---
run "compute" {
  command = plan

  # not-testable: application-insights.component.workspace - the module exposes no attribute for it; set through the module input, reviewed in the call

  # decision: application-insights.component.application_type
  assert {
    condition     = module.insights.resource.application_type == "web"
    error_message = "application-insights.component.application_type must be \"web\", got ${try(jsonencode(module.insights.resource.application_type), "unknown")}."
  }

  # decision: application-insights.component.sampling_percentage
  assert {
    condition     = module.insights.resource.sampling_percentage == 100
    error_message = "application-insights.component.sampling_percentage must be 100, got ${try(jsonencode(module.insights.resource.sampling_percentage), "unknown")}."
  }

  # decision: application-insights.component.daily_cap_gb
  assert {
    condition     = module.insights.resource.daily_data_cap_in_gb == 0
    error_message = "application-insights.component.daily_cap_gb must be 0, got ${try(jsonencode(module.insights.resource.daily_data_cap_in_gb), "unknown")}."
  }

  # decision: application-insights.component.store_client_ip
  assert {
    condition     = module.insights.resource.disable_ip_masking == false
    error_message = "application-insights.component.store_client_ip must be false, got ${try(jsonencode(module.insights.resource.disable_ip_masking), "unknown")}."
  }
}

# --- data_protection ---
run "data_protection" {
  command = plan

  # decision: log-analytics-workspace.cost.retention_days
  assert {
    condition     = module.workspace.resource.retention_in_days == 30
    error_message = "log-analytics-workspace.cost.retention_days must be 30, got ${try(jsonencode(module.workspace.resource.retention_in_days), "unknown")}."
  }

  # decision: log-analytics-workspace.cost.daily_quota_gb
  assert {
    condition     = module.workspace.resource.daily_quota_gb == -1
    error_message = "log-analytics-workspace.cost.daily_quota_gb must be -1, got ${try(jsonencode(module.workspace.resource.daily_quota_gb), "unknown")}."
  }

  # decision: log-analytics-workspace.cost.sku
  assert {
    condition     = module.workspace.resource.sku == "PerGB2018"
    error_message = "log-analytics-workspace.cost.sku must be \"PerGB2018\", got ${try(jsonencode(module.workspace.resource.sku), "unknown")}."
  }

  # not-testable: log-analytics-workspace.data_protection.immediate_purge_protection - the module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: log-analytics-workspace.data_protection.archive_to_storage - the module exposes no attribute for it; set through the module input, reviewed in the call
}

# --- identity ---
run "identity" {
  command = plan

  # not-testable: log-analytics-workspace.access.public_network_access - the module exposes no attribute for it; set through the module input, reviewed in the call

  # decision: log-analytics-workspace.access.local_auth
  assert {
    condition     = module.workspace.resource.local_authentication_enabled == false
    error_message = "log-analytics-workspace.access.local_auth must be false, got ${try(jsonencode(module.workspace.resource.local_authentication_enabled), "unknown")}."
  }

  # not-testable: log-analytics-workspace.access.rbac_only_access - the module exposes no attribute for it; set through the module input, reviewed in the call

  # not-testable: application-insights.identity.role_assignments - the role assignments are child resources of the module, which the root cannot read
}

# --- networking ---
run "networking" {
  command = plan

  # decision: application-insights.networking.public_network_access
  assert {
    condition     = module.insights.resource.internet_ingestion_enabled == false
    error_message = "application-insights.networking.public_network_access must be false, got ${try(jsonencode(module.insights.resource.internet_ingestion_enabled), "unknown")}."
  }
}

# --- security ---
run "security" {
  command = plan

  # decision: application-insights.security.local_authentication_disabled
  assert {
    condition     = module.insights.resource.local_authentication_disabled == true
    error_message = "application-insights.security.local_authentication_disabled must be true, got ${try(jsonencode(module.insights.resource.local_authentication_disabled), "unknown")}."
  }
}
