# The production stage, rendered from ../infra-spec.yaml: context: and every per-stage value
# for `production`. It is the only stage (context.environments: [production]). One state per
# stage: terraform init -backend-config="key=chatbot/production.tfstate".
environment         = "production"
location            = "westeurope"
workload            = "chatbot"
subscription_id     = "11111111-2222-3333-4444-555555555555"
resource_group_name = "rg-chatbot-prod-we"

# deployment.address_space and virtual-network.addressing.subnets
address_space = "10.20.0.0/16"
subnets = {
  "snet-endpoints" = { prefix = "10.20.0.0/27" }
  "snet-web"       = { prefix = "10.20.0.64/26" }
  "snet-mcp"       = { prefix = "10.20.0.128/26" }
  "snet-func"      = { prefix = "10.20.0.192/26" }
  "snet-aca"       = { prefix = "10.20.1.0/27" }
}

# Every resource's identity.role_assignments: who holds which role on it. The principal is
# the spec's key for it.
role_assignments = {
  "key-vault" = [
    { principal = "user-assigned-identity__web", role = "Key Vault Secrets User" },
    { principal = "user-assigned-identity__connector", role = "Key Vault Secrets User" },
  ]
  "storage-account__uploads" = [
    { principal = "user-assigned-identity__web", role = "Storage Blob Data Contributor" },
    { principal = "search-service", role = "Storage Blob Data Reader" },
  ]
  "storage-account__host" = [
    { principal = "user-assigned-identity__connector", role = "Storage Blob Data Owner" },
    { principal = "user-assigned-identity__connector", role = "Storage Table Data Contributor" },
    { principal = "user-assigned-identity__connector", role = "Storage Queue Data Contributor" },
  ]
  "foundry" = [
    { principal = "user-assigned-identity__web", role = "Cognitive Services OpenAI User" },
    { principal = "user-assigned-identity__connector", role = "Cognitive Services OpenAI User" },
    { principal = "search-service", role = "Cognitive Services OpenAI User" },
  ]
  "search-service" = [
    { principal = "user-assigned-identity__web", role = "Search Index Data Reader" },
    { principal = "user-assigned-identity__connector", role = "Search Index Data Contributor" },
  ]
  "container-registry" = [
    { principal = "user-assigned-identity__runner", role = "AcrPull" },
  ]
  "application-insights" = [
    { principal = "user-assigned-identity__connector", role = "Monitoring Metrics Publisher" },
  ]
}

cosmos_data_role_assignments = [
  { principal = "user-assigned-identity__web", role = "Cosmos DB Built-in Data Contributor" },
]

secret_placeholders = ["entra-client-secret"]
