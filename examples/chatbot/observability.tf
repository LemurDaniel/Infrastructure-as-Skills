# The workspace and the Application Insights component: observability_ownership: create.
# Every other resource's diagnostic setting points at the workspace.

data "naming_name" "workspace" {
  resource = "Azure::Microsoft.OperationalInsights/workspaces"
}

data "naming_name" "insights" {
  resource = "Azure::Microsoft.Insights/components"
}

module "workspace" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "~> 0.5.0"

  name                = data.naming_name.workspace.name
  location            = var.location
  resource_group_name = var.resource_group_name

  log_analytics_workspace_sku = "PerGB2018"
  # decision: log-analytics-workspace.cost.retention_days (deployment.log_retention_days)
  log_analytics_workspace_retention_in_days = 30
  # decision: log-analytics-workspace.cost.daily_quota_gb - -1 is no cap
  log_analytics_workspace_daily_quota_gb = -1

  # decision: log-analytics-workspace.access.public_network_access - both, or logs arrive
  # and nobody can read them; ingestion goes through the platform's monitor private link.
  log_analytics_workspace_internet_ingestion_enabled = false
  log_analytics_workspace_internet_query_enabled     = false
  # decision: log-analytics-workspace.access.local_auth - the module default is true
  log_analytics_workspace_local_authentication_enabled = false
  # decision: log-analytics-workspace.access.rbac_only_access
  log_analytics_workspace_allow_resource_only_permissions = false

  enable_telemetry = true
  tags             = local.tags
}

module "insights" {
  source  = "Azure/avm-res-insights-component/azurerm"
  version = "~> 0.5.0"

  name         = data.naming_name.insights.name
  location     = var.location
  parent_id    = data.azurerm_resource_group.this.id
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

  role_assignments = lookup(local.role_assignments_uai, "application-insights", {})

  enable_telemetry = true
  tags             = local.tags
}
