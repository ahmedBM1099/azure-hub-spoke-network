terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {
    storage {
      # The storage account has no public access and Terraform runs outside the VNet:
      # skip the provider's data-plane checks, which would fail with HTTP 403
      data_plane_available = false
    }
  }
  # Sandbox subscriptions often forbid registering resource providers
  resource_provider_registrations = "none"
}
