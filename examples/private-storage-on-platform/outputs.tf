output "id" {
  value = module.storage.resource_id
}

output "name" {
  value = module.storage.name
}

output "principal_id" {
  description = "System-assigned identity of the account, for grants it needs outward."
  value       = try(module.storage.resource.output.identity.principalId, null)
  sensitive   = true # inherited from the module's `resource` output
}

output "private_endpoints" {
  description = "Private endpoint id and name per sub-resource, keyed by sub-resource."
  value       = { for k, pe in module.storage.private_endpoints : k => { id = pe.id, name = pe.name } }
}
