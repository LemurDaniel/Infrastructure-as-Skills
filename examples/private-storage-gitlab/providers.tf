terraform {
  # The AVM storage module requires >= 1.10 (write-only arguments, ephemeral values).
  required_version = ">= 1.10"

  # One state per stage, selected at init by the backend key, never by a workspace:
  #   terraform init -backend-config="key=invoicing/production.tfstate"
  #   terraform plan -var-file=environments/production.tfvars
  # The backend's values (its storage account, its container, the key) are the
  # consuming repository's and arrive as -backend-config from the pipeline. The block
  # itself is empty and must exist: -backend-config without a backend block is ignored
  # without an error, and the state would be local. For a local run without a state:
  # terraform init -backend=false.
  backend "azurerm" {}

  required_providers {
    # The root's own use: the data blocks that reference the platform. The module
    # itself does not use azurerm at all.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
    # Required by the module (AzAPI-based since 0.7). Declared here so one init
    # resolves one version for the whole configuration and the lock file pins it.
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.11"
    }
    modtm = {
      source  = "Azure/modtm"
      version = "~> 0.3"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    naming = {
      source  = "LemurDaniel/naming"
      version = "~> 1.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id

  # Shared-key auth is off on the account (deployment.local_auth: disabled), so any
  # azurerm data-plane resource added beside the module has to reach it with Entra ID.
  # The module itself authenticates with Entra ID regardless.
  storage_use_azuread = true

  features {}
}

provider "azapi" {
  subscription_id = var.subscription_id
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
