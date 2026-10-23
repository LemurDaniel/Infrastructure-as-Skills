output "foundry" {
  description = "The Foundry account module."
  value       = module.foundry
  sensitive   = true
}

output "search" {
  description = "The search service module."
  value       = module.search
  sensitive   = true
}

output "search_principal_id" {
  description = "Principal of the search service system-assigned identity."
  value       = module.search.resource.identity[0].principal_id
  sensitive   = true
}

output "names" {
  description = "The rendered names, for the tests and the other families."
  value = {
    foundry          = data.naming_name.foundry.name
    search           = data.naming_name.search.name
    private_endpoint = { for k, v in data.naming_name.private_endpoint : k => v.name }
  }
}
output "foundry_id" {
  description = "Resource id of the Foundry account."
  value       = module.foundry.resource_id
}

output "search_id" {
  description = "Resource id of the search service."
  value       = module.search.resource_id
}

