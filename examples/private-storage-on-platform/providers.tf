terraform {
  required_version = ">= 1.7"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
    naming = {
      source  = "LemurDaniel/naming"
      version = "~> 1.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id

  # Shared-key auth is off on the account (deployment.local_auth: disabled), so the
  # provider itself has to reach the data plane with Entra ID.
  storage_use_azuread = true

  features {}
}

# The convention is declared once, for the whole configuration. `naming` points at
# the repository's own copy, so a provider upgrade cannot change a name.
provider "naming" {
  convention  = "default"
  naming      = "${path.module}/naming.yaml"
  random_seed = "${var.subscription_id}/${var.resource_group_name}"

  parameters = {
    location    = var.location
    environment = var.environment
    name        = var.workload
  }
}
