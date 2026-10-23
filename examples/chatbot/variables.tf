variable "environment" {
  description = "Deployment environment. Drives the rendered name and the tags."
  type        = string

  validation {
    condition     = contains(["development", "test", "qa", "uat", "integration", "staging", "preproduction", "production", "sandbox", "demo", "hotfix"], var.environment)
    error_message = "environment must be one of the keys of mappings.environment in naming.yaml."
  }
}

variable "location" {
  description = "Azure region. Part of every rendered name, so it must be mapped in naming.yaml."
  type        = string
}

variable "workload" {
  description = "Workload short name, rendered into every resource name. Instances of one kind append their own suffix to it, so keep it short: a storage account name is limited to 24 characters."
  type        = string

  validation {
    condition     = length(var.workload) <= 7
    error_message = "workload must be 7 characters or fewer: st + region + environment + workload + the instance suffix (uploads) + index fill a 24-character storage account name."
  }
}

variable "subscription_id" {
  description = "Subscription the deployment targets. A context value, so the same code renders against another subscription without edits."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group everything is placed in. Not created here."
  type        = string
}

variable "tags" {
  description = "The organisation's tag set, applied to every resource. Open in the spec: nothing stated yet."
  type        = map(string)
  default     = {}
}

# --- network (deployment.network_ownership: create) ---------------------------

variable "address_space" {
  description = "Address range of the workload's spoke network (deployment.address_space). Per stage."
  type        = string
}

variable "subnets" {
  description = "Subnets of the network (virtual-network.addressing.subnets), by name. Per stage."
  type = map(object({
    prefix = string
  }))
}

# --- access between the resources (every resource's identity.role_assignments) ---

variable "role_assignments" {
  description = <<-EOT
    Roles on each resource, keyed by the spec's resource key: who (a user-assigned identity's
    resource key, or the resource key of a resource with a system-assigned identity) holds which
    role on it. With shared keys and local authentication off, a resource nobody holds a role on
    is working as specified and unusable. Per stage.
  EOT
  type = map(list(object({
    principal = string
    role      = string
  })))
  default = {}
}

variable "cosmos_data_role_assignments" {
  description = "Cosmos DB's own data-plane roles (cosmos-db.identity.data_plane_role_assignments): the Azure role of the same name does not read an item. Role by built-in name, principal by user-assigned identity key."
  type = list(object({
    principal = string
    role      = string
  }))
  default = []
}

variable "secret_placeholders" {
  description = "Names of key vault secrets created as empty placeholders to be filled in later (key-vault.security.secret_placeholders). Never a value."
  type        = list(string)
  default     = []
}
