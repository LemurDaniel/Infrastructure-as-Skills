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
  parent_id = var.resource_group_id

  os_type = "Linux"
  # decision: function-app.hosting.plan_type - Flex Consumption
  sku_name = "FC1"
  # decision: function-app.hosting.zone_redundant - the module default is true, which a
  # region without the FCZONEREDUNDANCY capability rejects for FC1
  zone_balancing_enabled = true

  diagnostic_settings = {
    workspace = {
      workspace_resource_id = var.workspace_resource_id
      metrics               = [{ category = "AllMetrics" }]
    }
  }

  enable_telemetry = true
  tags             = var.tags
}

module "function" {
  source  = "Azure/avm-res-web-site/azurerm"
  version = "~> 0.24.0"

  name                     = data.naming_name.function.name
  location                 = var.location
  parent_id                = var.resource_group_id
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
  storage_account_name                     = var.host_storage_account_name
  storage_uses_managed_identity            = true
  storage_user_assigned_identity_client_id = var.identities["connector"].client_id
  storage_authentication_type              = "UserAssignedIdentity"
  storage_user_assigned_identity_id        = var.identities["connector"].resource_id
  # decision: function-app.storage.deployment_container
  storage_container_endpoint = "https://${var.host_storage_account_name}.blob.core.windows.net/app-package"

  # decision: function-app.networking.public_network_access - a bool
  public_network_access_enabled = false
  # decision: function-app.networking.vnet_integration / integration_subnet / vnet_route_all
  virtual_network_subnet_id = var.subnet_ids["snet-func"]
  vnet_route_all_traffic    = true
  private_endpoints = {
    sites = {
      name               = data.naming_name.private_endpoint["function"].name
      subnet_resource_id = var.subnet_ids["snet-endpoints"]
    }
  }
  # deployment.private_dns_records: policy - the platform policy writes the record
  private_endpoints_manage_dns_zone_group = false

  # decision: function-app.identity.managed_identity
  managed_identities = {
    user_assigned_resource_ids = [var.identities["connector"].resource_id]
  }
  key_vault_reference_identity = var.identities["connector"].resource_id

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
  application_insights_connection_string = var.application_insights_connection_string

  diagnostic_settings = {
    workspace = {
      workspace_resource_id = var.workspace_resource_id
      logs = [
        { category = "FunctionAppLogs" },
        { category = "AppServiceAuditLogs" },
      ]
      metrics = [{ category = "AllMetrics" }]
    }
  }

  enable_telemetry = true
  tags             = var.tags

  depends_on = [time_sleep.roles]
}
