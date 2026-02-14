# Container Registry Module Outputs

output "id" {
  description = "The ID of the container registry"
  value       = azurerm_container_registry.this.id
}

output "name" {
  description = "The name of the container registry"
  value       = azurerm_container_registry.this.name
}

output "login_server" {
  description = "The URL that can be used to log into the container registry"
  value       = azurerm_container_registry.this.login_server
}

output "admin_username" {
  description = "The admin username (null since admin is disabled)"
  value       = null
  sensitive   = true
}

output "admin_password" {
  description = "The admin password (null since admin is disabled)"
  value       = null
  sensitive   = true
}

output "identity" {
  description = "The identity block of the container registry (if configured)"
  value       = azurerm_container_registry.this.identity
}
