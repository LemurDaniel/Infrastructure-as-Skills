output "id" {
  value = azurerm_storage_account.this.id
}

output "name" {
  value = azurerm_storage_account.this.name
}

output "principal_id" {
  description = "System-assigned identity of the account, for grants it needs outward."
  value       = azurerm_storage_account.this.identity[0].principal_id
}

output "private_endpoint_ips" {
  description = "Private IP per sub-resource endpoint, keyed by sub-resource."
  value       = { for k, pe in azurerm_private_endpoint.storage : k => pe.private_service_connection[0].private_ip_address }
}
