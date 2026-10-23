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

variable "identities" {
  description = "The user-assigned identities by instance: the apps run as them."
  type = map(object({
    resource_id = string
    client_id   = string
  }))
}

variable "host_storage_account_name" {
  description = "Name of the function host storage account."
  type        = string
}

variable "application_insights_connection_string" {
  description = "Connection string of the Application Insights component."
  type        = string
}

variable "role_scope_ids" {
  description = "Ids of the resources the apps hold roles on; the module waits for the roles after they exist."
  type        = list(string)
}
