# The registry, two App Services (the web app and the MCP server), the connector function app
# and the code-interpreter container app.

# Role assignments take a while to be effective, and the apps use theirs while they are being
# created: the first revision pulls its image, the host opens its storage. Everything that
# holds a role the compute needs is created, then the apps wait.
resource "time_sleep" "roles" {
  # The roles on the other families' resources are waited for through role_scope_ids: the
  # sleep is replaced when any of them is.
  triggers = { scopes = join(",", var.role_scope_ids) }

  depends_on = [module.registry]

  create_duration = "60s"
}
