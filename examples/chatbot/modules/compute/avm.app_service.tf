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
  parent_id = var.resource_group_id

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
      workspace_resource_id = var.workspace_resource_id
      metrics               = [{ category = "AllMetrics" }]
    }
  }

  enable_telemetry = true
  tags             = var.tags
}

module "app" {
  source  = "Azure/avm-res-web-site/azurerm"
  version = "~> 0.24.0"

  for_each = local.app_services

  name                     = data.naming_name.app[each.key].name
  location                 = var.location
  parent_id                = var.resource_group_id
  kind                     = "webapp"
  os_type                  = "Linux"
  service_plan_resource_id = module.plan[each.key].resource_id

  # decision: app-service.networking.public_network_access - a bool on the module
  public_network_access_enabled = false
  # decision: app-service.networking.vnet_integration / integration_subnet
  virtual_network_subnet_id = var.subnet_ids[each.value.subnet]
  # decision: app-service.networking.vnet_route_all
  vnet_route_all_traffic = true

  private_endpoints = {
    sites = {
      name               = data.naming_name.private_endpoint[each.key].name
      subnet_resource_id = var.subnet_ids["snet-endpoints"]
    }
  }
  # deployment.private_dns_records: policy - the platform policy writes the record
  private_endpoints_manage_dns_zone_group = false

  # decision: app-service.identity.managed_identity - the web identity is shared by both apps
  managed_identities = {
    user_assigned_resource_ids = [var.identities["web"].resource_id]
  }
  # Key Vault references resolve with that identity.
  key_vault_reference_identity = var.identities["web"].resource_id

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
      workspace_resource_id = var.workspace_resource_id
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
  tags             = var.tags

  depends_on = [time_sleep.roles]
}
