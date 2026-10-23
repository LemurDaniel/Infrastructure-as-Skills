variable "location" {
  description = "Azure region."
  type        = string
}

variable "workload" {
  description = "Workload short name, rendered into every resource name."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group everything is placed in."
  type        = string
}

variable "tags" {
  description = "The tag set applied to every resource."
  type        = map(string)
}

variable "tenant_id" {
  description = "Tenant the vault belongs to."
  type        = string
}

variable "workspace_resource_id" {
  description = "Log Analytics workspace every diagnostic setting points at."
  type        = string
}

variable "subnet_ids" {
  description = "Resource ids of the network subnets, by name."
  type        = map(string)
}

variable "role_assignments_uai" {
  description = "Roles held by user-assigned identities, by resource key; built in the root from the identity family output."
  type = map(map(object({
    role_definition_id_or_name = string
    principal_id               = string
  })))
  default = {}
}

variable "secret_placeholders" {
  description = "Names of key vault secrets created as empty placeholders to be filled in later. Never a value."
  type        = list(string)
  default     = []
}
