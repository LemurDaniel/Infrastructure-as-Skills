output "registry" {
  description = "The container registry module."
  value       = module.registry
  sensitive   = true
}

output "app" {
  description = "The App Service app modules by instance."
  value       = module.app
  sensitive   = true
}

output "function" {
  description = "The function app module."
  value       = module.function
  sensitive   = true
}

output "container_environment" {
  description = "The Container Apps environment (authored, see the comment on it)."
  value       = azapi_resource.container_environment
}

output "container_app" {
  description = "The Container App module."
  value       = module.container_app
  sensitive   = true
}

output "names" {
  description = "The rendered names, for the tests and the other families."
  value = {
    registry         = data.naming_name.registry.name
    app              = { for k, v in data.naming_name.app : k => v.name }
    function         = data.naming_name.function.name
    private_endpoint = { for k, v in data.naming_name.private_endpoint : k => v.name }
  }
}
output "registry_login_server" {
  description = "Login server of the registry."
  value       = module.registry.login_server
}

output "web_app_id" {
  description = "Resource id of the web app."
  value       = module.app["web"].resource_id
}

