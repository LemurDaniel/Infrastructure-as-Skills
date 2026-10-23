output "identities" {
  description = "The user-assigned identities by instance (the AVM module objects)."
  value       = module.identity
}

output "names" {
  description = "The rendered names, for the tests and the other families."
  value = {
    identity = { for k, v in data.naming_name.identity : k => v.name }
  }
}
