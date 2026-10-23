output "foundry_id" {
  description = "Resource id of the Foundry account."
  value       = module.foundry.resource_id
}

output "search_id" {
  description = "Resource id of the search service."
  value       = module.search.resource_id
}

output "search_principal_id" {
  description = "Principal of the search service system-assigned identity."
  value       = module.search.resource.identity[0].principal_id
}
