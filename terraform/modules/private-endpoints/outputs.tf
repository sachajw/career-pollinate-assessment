#------------------------------------------------------------------------------
# Private Endpoints Module - outputs.tf
#------------------------------------------------------------------------------

output "key_vault_private_endpoint_id" {
  description = "Resource ID of the Key Vault private endpoint"
  value       = azurerm_private_endpoint.keyvault.id
}

output "key_vault_private_ip" {
  description = "Private IP address assigned to the Key Vault endpoint (resolves via Private DNS)"
  value       = azurerm_private_endpoint.keyvault.private_service_connection[0].private_ip_address
}

output "container_registry_private_endpoint_id" {
  description = "Resource ID of the Container Registry private endpoint"
  value       = azurerm_private_endpoint.acr.id
}

output "container_registry_private_ip" {
  description = "Private IP address assigned to the ACR endpoint (resolves via Private DNS)"
  value       = azurerm_private_endpoint.acr.private_service_connection[0].private_ip_address
}
