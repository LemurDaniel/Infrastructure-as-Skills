# The workspace and the Application Insights component: observability_ownership: create.
# Every other resource's diagnostic setting points at the workspace.

data "naming_name" "workspace" {
  resource = "Azure::Microsoft.OperationalInsights/workspaces"
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
  tags             = var.tags
}
