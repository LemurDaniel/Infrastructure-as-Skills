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
      subnet_resource_id = var.subnet_ids["snet-endpoints"]
    }
  }
  # deployment.private_dns_records: policy - the platform policy writes the record
  private_endpoints_manage_dns_zone_group = false

  # decision: container-registry.security.admin_enabled - inverse of local_auth
  admin_enabled = false
  # decision: container-registry.security.anonymous_pull_enabled
  anonymous_pull_enabled = false

  role_assignments = lookup(var.role_assignments_uai, "container-registry", {})

  diagnostic_settings = {
    workspace = {
      workspace_resource_id = var.workspace_resource_id
      logs = [
        { category = "ContainerRegistryRepositoryEvents" },
        { category = "ContainerRegistryLoginEvents" },
      ]
      metrics = [{ category = "AllMetrics" }]
    }
  }

  enable_telemetry = true
  tags             = var.tags
}
