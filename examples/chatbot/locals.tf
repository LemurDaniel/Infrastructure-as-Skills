locals {
  # Subnet ids by name, for the families that put an endpoint or an integration into one.
  subnet_ids = { for k, s in module.network.network.subnets : k => s.resource_id }

  # The set itself comes from the spec's context.tags, not from this file.
  tags = var.tags

  # Who holds a role on what. A principal is the spec's key for it: a user-assigned
  # identity is `user-assigned-identity__<instance>`, a resource with a system-assigned
  # identity is its own resource key (here only `search-service`).
  uai_principal_ids = { for k, m in module.identity.identities : "user-assigned-identity__${k}" => m.principal_id }

  # A module's role_assignments input is a map with static keys (the principal and the
  # role): a key must be known at plan time, the principal id behind it is not.
  #
  # Roles held by user-assigned identities, and roles held by the search service's own
  # identity, are two maps on purpose. The search service itself takes only the first: one
  # map holding both would make it depend on its own principal. The search service's roles
  # on the foundry account are built inside the ai family; the ones on other families'
  # resources need both ends and are wiring, so they are built here.
  role_assignments_uai = {
    for res, list in var.role_assignments : res => {
      for a in list : "${a.principal}/${a.role}" => {
        role_definition_id_or_name = a.role
        principal_id               = local.uai_principal_ids[a.principal]
      } if startswith(a.principal, "user-assigned-identity__")
    }
  }
  role_assignments_search = {
    for res, list in var.role_assignments : res => {
      for a in list : "${a.principal}/${a.role}" => {
        role_definition_id_or_name = a.role
        principal_id               = module.ai.search_principal_id
      } if a.principal == "search-service"
    }
  }
}
