#------------------------------------------------------------------------------
# Azure Resource Group Module - outputs.tf
#------------------------------------------------------------------------------
# Output definitions for the resource group module.
# These outputs are used by dependent modules and for troubleshooting.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Resource Group Outputs
#------------------------------------------------------------------------------

# id - The fully qualified Azure Resource Manager ID
# Used when referencing the resource group in other modules or for permissions
output "id" {
  description = "The Azure Resource Manager ID of the resource group"
  value       = azurerm_resource_group.this.id
}

# name - The name of the resource group
# Used when passing the resource group name to other modules
output "name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.this.name
}

# location - The Azure region of the resource group
# Used when creating resources in the same region
output "location" {
  description = "The Azure region of the resource group"
  value       = azurerm_resource_group.this.location
}
