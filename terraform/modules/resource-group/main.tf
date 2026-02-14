#------------------------------------------------------------------------------
# Azure Resource Group Module - main.tf
#------------------------------------------------------------------------------
# This module creates and manages an Azure Resource Group with standardized
# naming conventions and tagging requirements.
#
# Usage:
#   module "resource_group" {
#     source = "../../modules/resource-group"
#     name     = "rg-myapp-dev"
#     location = "eastus2"
#     tags     = { Environment = "dev" }
#   }
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Resource Group
#------------------------------------------------------------------------------
# A resource group is a logical container for Azure resources. All resources
# deployed to Azure must be placed in a resource group. This module enforces
# naming conventions (must start with 'rg-') and validates location against
# approved Azure regions.
#------------------------------------------------------------------------------
resource "azurerm_resource_group" "this" {
  # Resource group name - must follow naming convention (rg-{project}-{env})
  name = var.name

  # Azure region where the resource group will be created
  location = var.location

  # Tags applied to the resource group for cost allocation and management
  tags = var.tags
}
