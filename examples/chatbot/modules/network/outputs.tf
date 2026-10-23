output "subnet_ids" {
  description = "Resource ids of the subnets, by name."
  value       = { for k, s in module.network.subnets : k => s.resource_id }
}
