# One private endpoint per sub-resource, all into the endpoints subnet of the network. The
# convention's <?SUBNAME;-%s> token carries the sub-resource, so the index stays last:
# pep-we-prod-chatbotkv-vault-01.
locals {
  private_endpoints = {
    "uploads-blob" = { name = "uploads", sub = "blob" }
    "host-blob"    = { name = "host", sub = "blob" }
    "host-queue"   = { name = "host", sub = "queue" }
    "host-table"   = { name = "host", sub = "table" }
    "cosmos"       = { name = "cosmos", sub = "sql" }
  }
}

data "naming_name" "private_endpoint" {
  for_each = local.private_endpoints

  resource   = "Azure::Microsoft.Network/privateEndpoints"
  parameters = { name = "${var.workload}${each.value.name}", subname = each.value.sub }
}
