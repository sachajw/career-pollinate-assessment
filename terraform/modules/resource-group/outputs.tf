# Resource Group Outputs
# These outputs are used by dependent modules

output "id" {
  description = "The ID of the resource group"
  value       = azurerm_resource_group.this.id
}

output "name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.this.name
}

output "location" {
  description = "The Azure region of the resource group"
  value       = azurerm_resource_group.this.location
}
