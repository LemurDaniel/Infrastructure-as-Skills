# --- the code interpreter: Container Apps environment and one app ------------------

data "naming_name" "container_environment" {
  resource   = "Azure::Microsoft.App/managedEnvironments"
  parameters = { name = "${var.workload}runner" }
}

data "naming_name" "container_app" {
  resource   = "Azure::Microsoft.App/containerApps"
  parameters = { name = "${var.workload}runner" }
}

# The environment is rendered authored, not through the AVM module. `avm-res-app-managedenvironment`
# declares an ephemeral resource (the workspace's shared key) in every version, and Terraform's
# mock providers cannot plan a configuration that contains one - so a root calling it cannot be
# tested at all. The authored form is the module's own body, with the decisions as properties
# (spec: resources.container-apps._target_overrides).
resource "azapi_resource" "container_environment" {
  type      = "Microsoft.App/managedEnvironments@2025-07-01"
  name      = data.naming_name.container_environment.name
  location  = var.location
  parent_id = var.resource_group_id
  tags      = var.tags

  body = {
    properties = {
      # decision: container-apps.environment.workload_profile
      workloadProfiles = [
        { name = "Consumption", workloadProfileType = "Consumption" },
      ]
      # decision: container-apps.environment.zone_redundant
      zoneRedundant = true
      # decision: container-apps.environment.internal / infrastructure_subnet
      vnetConfiguration = {
        internal               = true
        infrastructureSubnetId = var.subnet_ids["snet-aca"]
      }
      # decision: container-apps.environment.public_network_access
      publicNetworkAccess = "Disabled"
      # decision: container-apps.environment.peer_traffic_encryption
      peerTrafficConfiguration = { encryption = { enabled = true } }
      # Logs through a diagnostic setting, not the workspace's shared key.
      appLogsConfiguration = { destination = "azure-monitor" }
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "container_environment" {
  name                       = "diag"
  target_resource_id         = azapi_resource.container_environment.id
  log_analytics_workspace_id = var.workspace_resource_id

  enabled_log {
    category = "ContainerAppConsoleLogs"
  }
  enabled_log {
    category = "ContainerAppSystemLogs"
  }
  enabled_metric {
    category = "AllMetrics"
  }
}

module "container_app" {
  source  = "Azure/avm-res-app-containerapp/azurerm"
  version = "~> 0.9.0"

  name                                  = data.naming_name.container_app.name
  resource_group_name                   = var.resource_group_name
  container_app_environment_resource_id = azapi_resource.container_environment.id

  workload_profile_name = "Consumption"
  # decision: container-apps.app.revision_mode
  revision_mode = "Single"

  template = {
    # decision: container-apps.app.min_replicas / max_replicas
    min_replicas = 2
    max_replicas = 10
    containers = [{
      name = "code-runner"
      # decision: container-apps.app.container_image - a tag, never latest
      image = "${module.registry.login_server}/code-runner:1.0.0"
      # decision: container-apps.app.container_size
      cpu    = 0.5
      memory = "1Gi"
    }]
  }

  # decision: container-apps.ingress.* - the Bicep module's defaults are external, HTTP, port 80
  ingress = {
    external_enabled           = false
    target_port                = 8080
    allow_insecure_connections = false
    traffic_weight = [{
      latest_revision = true
      percentage      = 100
    }]
  }

  # decision: container-apps.identity.managed_identity - user-assigned, so it holds AcrPull
  # before the first revision pulls the image
  managed_identities = {
    user_assigned_resource_ids = [var.identities["runner"].resource_id]
  }
  registries = [{
    server   = module.registry.login_server
    identity = var.identities["runner"].resource_id
  }]

  enable_telemetry = true
  tags             = var.tags

  depends_on = [time_sleep.roles]
}
