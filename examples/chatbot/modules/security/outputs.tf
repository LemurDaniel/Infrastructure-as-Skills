output "key_vault_resource_id" {
  description = "Resource id of the vault."
  value       = module.key_vault.resource_id
}

output "key_vault_uri" {
  description = "Vault URI."
  value       = module.key_vault.uri
}
