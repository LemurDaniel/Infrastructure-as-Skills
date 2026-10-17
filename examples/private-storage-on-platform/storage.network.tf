# One name per sub-resource: the convention's <?SUBNAME;-%s> token carries the
# sub-resource, so the index stays last - pep-we-prod-invoicing-blob-01.
data "naming_name" "private_endpoint" {
  for_each = toset(var.private_endpoint_subresources)

  resource   = "Azure::Microsoft.Network/privateEndpoints"
  parameters = { subname = each.key }
}

# One endpoint per sub-resource, into the platform's private-endpoint subnet.
resource "azurerm_private_endpoint" "storage" {
  for_each = toset(var.private_endpoint_subresources)

  name                = data.naming_name.private_endpoint[each.key].name
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = data.azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-${each.key}"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = [each.key]
    is_manual_connection           = false
  }

  # deployment.private_dns_records: policy - the landing zone's DeployIfNotExists
  # policy attaches the privatelink zone and writes the record. No zone group
  # here, or two writers own one record; and ignore the one the policy adds.
  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }

  tags = local.tags
}
