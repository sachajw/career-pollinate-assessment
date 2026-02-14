#------------------------------------------------------------------------------
# Azure Container Registry Module - outputs.tf
#------------------------------------------------------------------------------
# Output definitions for the container registry module.
# These outputs are used by dependent modules (Container Apps, CI/CD) and
# for troubleshooting and integration purposes.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Registry Identification Outputs
#------------------------------------------------------------------------------

# id - The Azure Resource Manager ID of the container registry
# Used for RBAC role assignments and resource references
output "id" {
  description = "The Azure Resource Manager ID of the container registry"
  value       = azurerm_container_registry.this.id
}

# name - The name of the container registry
# Used in scripts and for display purposes
output "name" {
  description = "The name of the container registry"
  value       = azurerm_container_registry.this.name
}

# login_server - The URL for logging into the registry
# Used in docker login commands and CI/CD configurations
# Format: <registry-name>.azurecr.io
output "login_server" {
  description = "The URL that can be used to log into the container registry"
  value       = azurerm_container_registry.this.login_server
}

#------------------------------------------------------------------------------
# Admin Credentials (Null - Admin Disabled)
#------------------------------------------------------------------------------
# These outputs return null because admin_enabled = false
# We use Managed Identity for authentication instead of admin credentials
# These are included for API compatibility with modules expecting these outputs
#------------------------------------------------------------------------------

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

#------------------------------------------------------------------------------
# Identity Output
#------------------------------------------------------------------------------

# identity - The managed identity configuration of the registry
# Used for customer-managed encryption key scenarios
output "identity" {
  description = "The identity block of the container registry (if configured)"
  value       = azurerm_container_registry.this.identity
}
