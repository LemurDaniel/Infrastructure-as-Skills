output "web_app_id" {
  value = module.compute.web_app_id
}

output "key_vault_uri" {
  value = module.security.key_vault_uri
}

output "foundry_id" {
  value = module.ai.foundry_id
}

output "search_id" {
  value = module.ai.search_id
}

output "cosmos_endpoint" {
  value = module.data.cosmos_endpoint
}

output "registry_login_server" {
  value = module.compute.registry_login_server
}

output "identity_ids" {
  description = "The user-assigned identities by instance, for grants from outside this root."
  value       = { for k, m in module.identity.identities : k => m.resource_id }
}
