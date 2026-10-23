# The family's providers are the union of its AVM modules' requirements (the root's list, less
# what the family does not call). Declared here and configured in the root only: a provider
# block belongs to the root. A test file mocks them, which needs them declared.
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
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
    naming = {
      source  = "LemurDaniel/naming"
      version = "~> 1.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }
}
