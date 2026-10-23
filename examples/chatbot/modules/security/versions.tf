# Declared here and configured in the root: a provider block belongs to the root only.
terraform {
  required_providers {
    naming = {
      source  = "LemurDaniel/naming"
      version = "~> 1.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
  }
}
