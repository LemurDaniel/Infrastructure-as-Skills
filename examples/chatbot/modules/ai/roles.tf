# Roles the search service's own identity holds on the foundry account: the identity exists
# only once the service does, so these are built here, inside the family. The roles it holds
# on resources of other families are built in the root (role_assignments_search there).
locals {
  role_assignments_search = {
    for res, list in var.role_assignments : res => {
      for a in list : "${a.principal}/${a.role}" => {
        role_definition_id_or_name = a.role
        principal_id               = module.search.resource.identity[0].principal_id
      } if a.principal == "search-service"
    }
  }
}
