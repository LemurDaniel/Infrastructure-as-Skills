terraform {
  # The AVM Key Vault module needs >= 1.11, the others >= 1.9 or 1.10.
  required_version = ">= 1.11"

  # One state per stage, selected at init by the backend key, never by a workspace:
  #   terraform init -backend-config="key=chatbot/production.tfstate"
  #   terraform plan -var-file=environments/production.tfvars
  # The block is empty and must exist: -backend-config without a backend block is ignored
  # without an error, and the state would be local. A run without a state:
  # terraform init -backend=false.
  backend "azurerm" {}

  required_providers {
    # Six of the AVM modules in this root (Key Vault, identity, search, registry, Container
    # Apps environment, Cosmos DB) are azurerm-based and constrain it to 4.x, so the root
    # cannot be on 5.x - the union of the modules' requirements decides. >= 4.81 is the
    # highest floor among them (Key Vault, container registry).
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
    # The other modules are AzAPI-based (storage, virtual network, App Service, Foundry,
    # Container App, Application Insights, network security group).
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
    modtm = {
      source  = "Azure/modtm"
      version = "~> 0.3"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
    naming = {
      source  = "LemurDaniel/naming"
      version = "~> 1.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id

  # Shared-key auth is off on every storage account (deployment.local_auth: disabled), so
  # any azurerm data-plane resource added beside a module has to reach it with Entra ID.
  storage_use_azuread = true

  features {}
}

provider "azapi" {
  subscription_id = var.subscription_id
}

# The convention is declared once, for the whole configuration. `naming` points at the
# repository's own copy, so a provider upgrade cannot change a name.
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
