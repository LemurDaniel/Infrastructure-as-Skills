data "naming_name" "insights" {
  resource = "Azure::Microsoft.Insights/components"
}

module "insights" {
  source  = "Azure/avm-res-insights-component/azurerm"
  version = "~> 0.5.0"

  name         = data.naming_name.insights.name
  location     = var.location
  parent_id    = var.resource_group_id
  workspace_id = module.workspace.resource_id

  application_type = "web"
  # decision: application-insights.component.sampling_percentage / daily_cap_gb - the
  # module default for the cap is 100 GB, 0 is unlimited
  sampling_percentage  = 100
  daily_data_cap_in_gb = 0
  # decision: application-insights.component.store_client_ip - disabling the masking stores the address
  disable_ip_masking = false

  # decision: application-insights.networking.public_network_access - both bools, the
  # module default is true for each. The platform's Azure Monitor Private Link Scope is
  # open (spec: open) - until it is named, a closed component receives nothing.
  internet_ingestion_enabled = false
  internet_query_enabled     = false

  # decision: application-insights.security.local_authentication_disabled - the module
  # default is false
  local_authentication_disabled = true

  # The workspace governs retention; the component's own value follows it.
  retention_in_days = 30

  role_assignments = lookup(var.role_assignments_uai, "application-insights", {})

  enable_telemetry = true
  tags             = var.tags
}
