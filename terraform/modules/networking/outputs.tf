#------------------------------------------------------------------------------
# Networking Module - outputs.tf
#------------------------------------------------------------------------------

output "vnet_id" {
  description = "Resource ID of the Virtual Network"
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the Virtual Network"
  value       = azurerm_virtual_network.this.name
}

output "private_endpoint_subnet_id" {
  description = "Resource ID of the private endpoints subnet (used by azurerm_private_endpoint)"
  value       = azurerm_subnet.private_endpoints.id
}

output "container_app_subnet_id" {
  description = "Resource ID of the Container App environment subnet (used for VNet injection)"
  value       = azurerm_subnet.container_app.id
}
