output "key_vault" {
  description = "The Key Vault module."
  value       = module.key_vault
  sensitive   = true
}

output "names" {
  description = "The rendered names, for the tests and the other families."
  value = {
    key_vault        = data.naming_name.key_vault.name
    private_endpoint = { for k, v in data.naming_name.private_endpoint : k => v.name }
  }
}
output "key_vault_uri" {
  description = "Vault URI."
  value       = module.key_vault.uri
}

