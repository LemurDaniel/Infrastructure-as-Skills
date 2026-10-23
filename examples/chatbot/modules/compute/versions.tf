# Declared here and configured in the root: a provider block belongs to the root only.
terraform {
  required_providers {
    naming = {
      source  = "LemurDaniel/naming"
      version = "~> 1.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }
}
