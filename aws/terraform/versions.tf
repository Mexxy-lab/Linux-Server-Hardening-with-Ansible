terraform {
  # Require a modern Terraform version.
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Use the region configured in terraform.tfvars.
provider "aws" {
  region = var.aws_region
}
