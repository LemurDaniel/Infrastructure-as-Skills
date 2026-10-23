output "web_app_id" {
  description = "Resource id of the web app."
  value       = module.app["web"].resource_id
}

output "registry_login_server" {
  description = "Login server of the registry."
  value       = module.registry.login_server
}
