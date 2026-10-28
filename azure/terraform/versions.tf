terraform {
  # Require a modern Terraform version.
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Read the target subscription from terraform.tfvars.
provider "azurerm" {
  subscription_id = var.subscription_id

  features {}
}