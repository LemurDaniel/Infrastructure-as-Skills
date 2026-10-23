output "network" {
  description = "The virtual network module."
  value       = module.network
  sensitive   = true
}

output "nsg" {
  description = "The network security group modules by purpose."
  value       = module.nsg
  sensitive   = true
}

output "names" {
  description = "The rendered names, for the tests and the other families."
  value = {
    network = data.naming_name.network.name
    nsg     = { for k, v in data.naming_name.nsg : k => v.name }
  }
}
