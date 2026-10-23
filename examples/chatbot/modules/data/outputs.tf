output "storage" {
  description = "The storage account modules by instance."
  value       = module.storage
  sensitive   = true
}

output "cosmos" {
  description = "The Cosmos DB module."
  value       = module.cosmos
  sensitive   = true
}

output "names" {
  description = "The rendered names, for the tests and the other families."
  value = {
    storage_account  = { for k, v in data.naming_name.storage_account : k => v.name }
    cosmos           = data.naming_name.cosmos.name
    private_endpoint = { for k, v in data.naming_name.private_endpoint : k => v.name }
  }
}
output "cosmos_endpoint" {
  description = "Endpoint of the Cosmos DB account."
  value       = module.cosmos.endpoint
}

