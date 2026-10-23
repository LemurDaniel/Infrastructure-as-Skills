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

variable "address_space" {
  description = "Address range of the workload spoke network. Per stage."
  type        = string
}

variable "subnets" {
  description = "Subnets of the network, by name. Per stage."
  type = map(object({
    prefix = string
  }))
}
