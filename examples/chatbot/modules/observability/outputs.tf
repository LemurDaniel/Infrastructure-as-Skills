output "workspace_resource_id" {
  description = "Log Analytics workspace every diagnostic setting points at."
  value       = module.workspace.resource_id
}

output "insights_resource_id" {
  description = "Application Insights component."
  value       = module.insights.resource_id
}

output "insights_connection_string" {
  description = "Connection string of the component."
  value       = module.insights.connection_string
  sensitive   = true
}
