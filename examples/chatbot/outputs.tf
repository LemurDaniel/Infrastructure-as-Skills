output "web_app_id" {
  value = module.app["web"].resource_id
}

output "key_vault_uri" {
  value = module.key_vault.uri
}

output "foundry_id" {
  value = module.foundry.resource_id
}

output "search_id" {
  value = module.search.resource_id
}

output "cosmos_endpoint" {
  value = module.cosmos.endpoint
}

output "registry_login_server" {
  value = module.registry.login_server
}

output "identity_ids" {
  description = "The user-assigned identities by instance, for grants from outside this root."
  value       = { for k, m in module.identity : k => m.resource_id }
}
