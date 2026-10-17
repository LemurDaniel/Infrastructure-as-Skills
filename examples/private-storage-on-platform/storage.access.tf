# Data-plane roles, scoped to the container where the consumer allows it and
# never to the subscription. Empty until the consumer is named (spec: open).
resource "azurerm_role_assignment" "data" {
  for_each = { for ra in var.role_assignments : "${ra.principal_id}-${ra.role}" => ra }

  scope                = coalesce(each.value.scope, azurerm_storage_account.this.id)
  role_definition_name = each.value.role
  principal_id         = each.value.principal_id
}
