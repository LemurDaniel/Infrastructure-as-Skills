# One private endpoint per sub-resource, all into the endpoints subnet of this network. The
# convention's <?SUBNAME;-%s> token carries the sub-resource, so the index stays last:
# pep-we-prod-chatbotkv-vault-01. `name` tells the resources of the workload apart, as the
# plan and the app names do.

locals {
  private_endpoints = {
    "kv"           = { name = "kv", sub = "vault" }
    "uploads-blob" = { name = "uploads", sub = "blob" }
    "host-blob"    = { name = "host", sub = "blob" }
    "host-queue"   = { name = "host", sub = "queue" }
    "host-table"   = { name = "host", sub = "table" }
    "cosmos"       = { name = "cosmos", sub = "sql" }
    "search"       = { name = "search", sub = "searchservice" }
    "foundry"      = { name = "foundry", sub = "account" }
    "registry"     = { name = "registry", sub = "registry" }
    "web"          = { name = "web", sub = "sites" }
    "mcp"          = { name = "mcp", sub = "sites" }
    "function"     = { name = "func", sub = "sites" }
  }
}

data "naming_name" "private_endpoint" {
  for_each = local.private_endpoints

  resource   = "Azure::Microsoft.Network/privateEndpoints"
  parameters = { name = "${var.workload}${each.value.name}", subname = each.value.sub }
}
