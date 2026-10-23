# The registry, two App Services (the web app and the MCP server), the connector function app
# and the code-interpreter container app.

# Role assignments take a while to be effective, and the apps use theirs while they are being
# created: the first revision pulls its image, the host opens its storage. Everything that
# holds a role the compute needs is created, then the apps wait.
resource "time_sleep" "roles" {
  depends_on = [
    module.registry,
    module.storage,
    module.key_vault,
    module.search,
    module.foundry,
    module.insights,
    azurerm_cosmosdb_sql_role_assignment.this,
  ]

  create_duration = "60s"
}

# --- container registry -------------------------------------------------------

data "naming_name" "registry" {
  resource = "Azure::Microsoft.ContainerRegistry/registries"
}

module "registry" {
  source  = "Azure/avm-res-containerregistry-registry/azurerm"
  version = "~> 0.8.0"

  name                = data.naming_name.registry.name
  location            = var.location
  resource_group_name = var.resource_group_name

  # decision: container-registry.registry.sku - Premium, forced by the private posture
  sku = "Premium"
  # decision: container-registry.registry.zone_redundant - fixed at creation
  zone_redundancy_enabled = true
  georeplications         = []
  # decision: container-registry.registry.retention_untagged_days - Bicep's default is 15
  retention_policy_in_days = 7

  # decision: container-registry.networking.public_network_access - a bool, module default true
  public_network_access_enabled = false
  # decision: container-registry.networking.network_rule_bypass
  network_rule_bypass_option = "None"
  # decision: container-registry.networking.export_policy_enabled
  export_policy_enabled = false
  private_endpoints = {
    registry = {
      name               = data.naming_name.private_endpoint["registry"].name
      subnet_resource_id = module.network.subnets["snet-endpoints"].resource_id
    }
  }
  # deployment.private_dns_records: policy - the platform policy writes the record
  private_endpoints_manage_dns_zone_group = false

  # decision: container-registry.security.admin_enabled - inverse of local_auth
  admin_enabled = false
  # decision: container-registry.security.anonymous_pull_enabled
  anonymous_pull_enabled = false

  role_assignments = lookup(local.role_assignments_uai, "container-registry", {})

  diagnostic_settings = {
    workspace = {
      workspace_resource_id = module.workspace.resource_id
      logs = [
        { category = "ContainerRegistryRepositoryEvents" },
        { category = "ContainerRegistryLoginEvents" },
      ]
      metrics = [{ category = "AllMetrics" }]
    }
  }

  enable_telemetry = true
  tags             = local.tags
}

# --- App Service: the web app and the MCP server ---------------------------------

locals {
  # Two apps, each on a plan of its own: a delegated subnet is exclusive to one plan.
  app_services = {
    web = {
      subnet = "snet-web"
      stack  = { python = { python_version = "3.12" } }
    }
    mcp = {
      subnet = "snet-mcp"
      stack  = { node = { node_version = "22-lts" } }
    }
  }
}

data "naming_name" "plan" {
  for_each = local.app_services

  resource   = "Azure::Microsoft.Web/serverFarms"
  parameters = { name = "${var.workload}${each.key}" }
}

data "naming_name" "app" {
  for_each = local.app_services

  resource   = "Azure::Microsoft.Web/sites"
  parameters = { name = "${var.workload}${each.key}" }
}

module "plan" {
  source  = "Azure/avm-res-web-serverfarm/azurerm"
  version = "~> 2.0"

  for_each = local.app_services

  name      = data.naming_name.plan[each.key].name
  location  = var.location
  parent_id = data.azurerm_resource_group.this.id

  # decision: app-service.hosting.os_type
  os_type = "Linux"
  # decision: app-service.hosting.sku - the module default is P1v2
  sku_name = "P1v3"
  # decision: app-service.hosting.zone_redundant - the module default is true, which a Basic
  # size rejects
  zone_balancing_enabled = true
  # decision: app-service.hosting.instance_count - zone redundancy needs two or more
  worker_count = 2

  diagnostic_settings = {
    workspace = {
      workspace_resource_id = module.workspace.resource_id
      metrics               = [{ category = "AllMetrics" }]
    }
  }

  enable_telemetry = true
  tags             = local.tags
}

module "app" {
  source  = "Azure/avm-res-web-site/azurerm"
  version = "~> 0.24.0"

  for_each = local.app_services

  name                     = data.naming_name.app[each.key].name
  location                 = var.location
  parent_id                = data.azurerm_resource_group.this.id
  kind                     = "webapp"
  os_type                  = "Linux"
  service_plan_resource_id = module.plan[each.key].resource_id

  # decision: app-service.networking.public_network_access - a bool on the module
  public_network_access_enabled = false
  # decision: app-service.networking.vnet_integration / integration_subnet
  virtual_network_subnet_id = module.network.subnets[each.value.subnet].resource_id
  # decision: app-service.networking.vnet_route_all
  vnet_route_all_traffic = true

  private_endpoints = {
    sites = {
      name               = data.naming_name.private_endpoint[each.key].name
      subnet_resource_id = module.network.subnets["snet-endpoints"].resource_id
    }
  }
  # deployment.private_dns_records: policy - the platform policy writes the record
  private_endpoints_manage_dns_zone_group = false

  # decision: app-service.identity.managed_identity - the web identity is shared by both apps
  managed_identities = {
    user_assigned_resource_ids = [module.identity["web"].resource_id]
  }
  # Key Vault references resolve with that identity.
  key_vault_reference_identity = module.identity["web"].resource_id

  https_only = true
  # decision: app-service.security.basic_auth_enabled - the SCM default is true
  ftp_publish_basic_authentication_enabled = false
  scm_publish_basic_authentication_enabled = false

  site_config = {
    always_on                     = true
    http2_enabled                 = true
    ftps_state                    = "Disabled"
    minimum_tls_version           = "1.2"
    scm_minimum_tls_version       = "1.2"
    ip_restriction_default_action = "Deny"
    scm_use_main_ip_restriction   = true

    application_stack = each.value.stack
  }

  diagnostic_settings = {
    workspace = {
      workspace_resource_id = module.workspace.resource_id
      logs = [
        { category = "AppServiceHTTPLogs" },
        { category = "AppServiceAppLogs" },
        { category = "AppServiceAuditLogs" },
        { category = "AppServiceIPSecAuditLogs" },
        { category = "AppServicePlatformLogs" },
      ]
      metrics = [{ category = "AllMetrics" }]
    }
  }

  enable_telemetry = true
  tags             = local.tags

  depends_on = [time_sleep.roles]
}

# --- the connector function app (Flex Consumption) -----------------------------

data "naming_name" "function_plan" {
  resource   = "Azure::Microsoft.Web/serverFarms"
  parameters = { name = "${var.workload}func" }
}

data "naming_name" "function" {
  resource   = "Azure::Microsoft.Web/sites::function"
  parameters = { name = "${var.workload}func" }
}

module "function_plan" {
  source  = "Azure/avm-res-web-serverfarm/azurerm"
  version = "~> 2.0"

  name      = data.naming_name.function_plan.name
  location  = var.location
  parent_id = data.azurerm_resource_group.this.id

  os_type = "Linux"
  # decision: function-app.hosting.plan_type - Flex Consumption
  sku_name = "FC1"
  # decision: function-app.hosting.zone_redundant - the module default is true, which a
  # region without the FCZONEREDUNDANCY capability rejects for FC1
  zone_balancing_enabled = true

  diagnostic_settings = {
    workspace = {
      workspace_resource_id = module.workspace.resource_id
      metrics               = [{ category = "AllMetrics" }]
    }
  }

  enable_telemetry = true
  tags             = local.tags
}

module "function" {
  source  = "Azure/avm-res-web-site/azurerm"
  version = "~> 0.24.0"

  name                     = data.naming_name.function.name
  location                 = var.location
  parent_id                = data.azurerm_resource_group.this.id
  kind                     = "functionapp"
  os_type                  = "Linux"
  service_plan_resource_id = module.function_plan.resource_id

  function_app_uses_fc1 = true
  # decision: function-app.hosting.runtime_stack / runtime_version
  fc1_runtime_name    = "python"
  fc1_runtime_version = "3.12"
  # decision: function-app.hosting.max_instance_count / always_ready_instances / instance_memory_mb
  maximum_instance_count = 20
  instance_memory_in_mb  = 2048
  always_ready           = { http = { instance_count = 1 } }

  # decision: function-app.storage.host_storage_account / host_storage_auth - identity, never
  # the storage key. Two connections on Flex: the host's own, and the deployment package.
  storage_account_name                     = module.storage["host"].name
  storage_uses_managed_identity            = true
  storage_user_assigned_identity_client_id = module.identity["connector"].client_id
  storage_authentication_type              = "UserAssignedIdentity"
  storage_user_assigned_identity_id        = module.identity["connector"].resource_id
  # decision: function-app.storage.deployment_container
  storage_container_endpoint = "https://${module.storage["host"].name}.blob.core.windows.net/app-package"

  # decision: function-app.networking.public_network_access - a bool
  public_network_access_enabled = false
  # decision: function-app.networking.vnet_integration / integration_subnet / vnet_route_all
  virtual_network_subnet_id = module.network.subnets["snet-func"].resource_id
  vnet_route_all_traffic    = true
  private_endpoints = {
    sites = {
      name               = data.naming_name.private_endpoint["function"].name
      subnet_resource_id = module.network.subnets["snet-endpoints"].resource_id
    }
  }
  # deployment.private_dns_records: policy - the platform policy writes the record
  private_endpoints_manage_dns_zone_group = false

  # decision: function-app.identity.managed_identity
  managed_identities = {
    user_assigned_resource_ids = [module.identity["connector"].resource_id]
  }
  key_vault_reference_identity = module.identity["connector"].resource_id

  https_only = true
  # decision: function-app.security.basic_auth_enabled - the SCM default is true
  ftp_publish_basic_authentication_enabled = false
  scm_publish_basic_authentication_enabled = false
  site_config = {
    minimum_tls_version           = "1.2"
    scm_minimum_tls_version       = "1.2"
    ip_restriction_default_action = "Deny"
    scm_use_main_ip_restriction   = true
  }

  # decision: function-app.security.application_insights
  application_insights_connection_string = module.insights.connection_string

  diagnostic_settings = {
    workspace = {
      workspace_resource_id = module.workspace.resource_id
      logs = [
        { category = "FunctionAppLogs" },
        { category = "AppServiceAuditLogs" },
      ]
      metrics = [{ category = "AllMetrics" }]
    }
  }

  enable_telemetry = true
  tags             = local.tags

  depends_on = [time_sleep.roles]
}

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
  parent_id = data.azurerm_resource_group.this.id
  tags      = local.tags

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
        infrastructureSubnetId = module.network.subnets["snet-aca"].resource_id
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
  log_analytics_workspace_id = module.workspace.resource_id

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
    user_assigned_resource_ids = [module.identity["runner"].resource_id]
  }
  registries = [{
    server   = module.registry.login_server
    identity = module.identity["runner"].resource_id
  }]

  enable_telemetry = true
  tags             = local.tags

  depends_on = [time_sleep.roles]
}
