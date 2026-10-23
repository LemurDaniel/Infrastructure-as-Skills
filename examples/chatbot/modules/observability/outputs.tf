output "workspace" {
  description = "The Log Analytics workspace module."
  value       = module.workspace
  sensitive   = true
}

output "insights" {
  description = "The Application Insights module."
  value       = module.insights
  sensitive   = true
}

output "names" {
  description = "The rendered names, for the tests and the other families."
  value = {
    workspace = data.naming_name.workspace.name
    insights  = data.naming_name.insights.name
  }
}
