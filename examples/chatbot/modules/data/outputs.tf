output "storage_resource_ids" {
  description = "Storage account ids by instance."
  value       = { for k, m in module.storage : k => m.resource_id }
}

output "host_storage_account_name" {
  description = "Name of the function host storage account."
  value       = module.storage["host"].name
}

output "cosmos_resource_id" {
  description = "Resource id of the Cosmos DB account."
  value       = module.cosmos.resource_id
}

output "cosmos_endpoint" {
  description = "Endpoint of the Cosmos DB account."
  value       = module.cosmos.endpoint
}
