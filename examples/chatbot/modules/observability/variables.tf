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

variable "resource_group_id" {
  description = "Id of the resource group. The AzAPI-based modules take it as parent_id."
  type        = string
}

variable "role_assignments_uai" {
  description = "Roles held by user-assigned identities, by resource key; built in the root from the identity family output."
  type = map(map(object({
    role_definition_id_or_name = string
    principal_id               = string
  })))
  default = {}
}
