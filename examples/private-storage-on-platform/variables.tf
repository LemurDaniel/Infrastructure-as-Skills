variable "environment" {
  description = "Deployment environment. Drives the rendered name, the tags and several security defaults."
  type        = string

  validation {
    # The keys of mappings.environment in naming.yaml - an environment the
    # convention cannot abbreviate cannot be named.
    condition     = contains(["development", "test", "qa", "uat", "integration", "staging", "preproduction", "production", "sandbox", "demo", "hotfix"], var.environment)
    error_message = "environment must be one of the keys of mappings.environment in naming.yaml."
  }
}

variable "location" {
  description = "Azure region. Part of every rendered name, so it must be mapped in naming.yaml."
  type        = string
}

variable "workload" {
  description = "Workload short name, rendered into every resource name. 15 characters at most, or the storage account name exceeds 24."
  type        = string

  validation {
    condition     = length(var.workload) <= 15
    error_message = "workload must be 15 characters or fewer: st + region + environment + index leave no more room in a 24-character storage account name."
  }
}

variable "subscription_id" {
  description = "Subscription the deployment targets. A context value, so the same code renders against another subscription without edits."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group the account is placed in. Not created here."
  type        = string
}

variable "tags" {
  description = "The organisation's tag set, applied to every resource. Open in the spec: nothing stated yet."
  type        = map(string)
  default     = {}
}

# --- platform the deployment references, never manages ----------------------

variable "vnet_name" {
  description = "Existing hub virtual network holding the private-endpoint subnet (deployment.existing_vnet)."
  type        = string
}

variable "network_resource_group_name" {
  description = "Resource group of the hub virtual network."
  type        = string
}

variable "private_endpoint_subnet_name" {
  description = "Existing subnet in the hub that carries the deployment's private endpoints (deployment.private_endpoint_subnet)."
  type        = string
}

variable "workspace_name" {
  description = "Existing central Log Analytics workspace receiving diagnostics (deployment.diagnostics_destination)."
  type        = string
}

variable "workspace_resource_group_name" {
  description = "Resource group of the central Log Analytics workspace."
  type        = string
}

# --- storage account decisions the caller may still vary ---------------------

variable "replication" {
  description = "Replication of the account for this stage (storage-account.data_protection.replication): ZRS in production, LRS in the non-production stages while non_production_savings is on. Per stage, from environments/<stage>.tfvars."
  type        = string

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS"], var.replication)
    error_message = "replication must be one of LRS, ZRS, GRS, GZRS."
  }
}

variable "private_endpoint_subresources" {
  description = "Storage services that get a private endpoint. One endpoint and one DNS record per entry, so list only what is used."
  type        = list(string)
  default     = ["blob"]

  validation {
    condition     = alltrue([for s in var.private_endpoint_subresources : contains(["blob", "file", "queue", "table", "dfs", "web"], s)])
    error_message = "Each entry must be one of blob, file, queue, table, dfs, web."
  }
}

variable "role_assignments" {
  description = "Data-plane role assignments on the account, role by name. Empty means a working account nobody can read - open in the spec until the consumer is named. A container-scoped assignment goes on the module's containers input, not here."
  type = list(object({
    principal_id = string
    role         = string
  }))
  default = []
}
