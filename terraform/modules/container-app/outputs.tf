#------------------------------------------------------------------------------
# Azure Container App Module - outputs.tf
#------------------------------------------------------------------------------
# Output definitions for the Container App module.
# These outputs are used for:
# - Application URL access
# - RBAC role assignments in other modules
# - Integration with monitoring and alerting
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Environment Outputs
#------------------------------------------------------------------------------

# environment_id - The Azure Resource Manager ID of the environment
# Used for cross-resource references and dependencies
output "environment_id" {
  description = "The ID of the container app environment"
  value       = azurerm_container_app_environment.this.id
}

# environment_name - The name of the environment
output "environment_name" {
  description = "The name of the container app environment"
  value       = azurerm_container_app_environment.this.name
}

# environment_default_domain - The default domain for apps in this environment
# Used to construct FQDNs for container apps
output "environment_default_domain" {
  description = "The default domain of the container app environment"
  value       = azurerm_container_app_environment.this.default_domain
}

# environment_static_ip - The static IP address of the environment
# Useful for firewall rules and network configuration
output "environment_static_ip" {
  description = "The static IP address of the container app environment"
  value       = azurerm_container_app_environment.this.static_ip_address
}

#------------------------------------------------------------------------------
# Container App Outputs
#------------------------------------------------------------------------------

# id - The Azure Resource Manager ID of the container app
# Used for RBAC and resource references
output "id" {
  description = "The ID of the container app"
  value       = azurerm_container_app.this.id
}

# name - The name of the container app
output "name" {
  description = "The name of the container app"
  value       = azurerm_container_app.this.name
}

# latest_revision_name - The name of the current active revision
# Useful for debugging and deployment tracking
output "latest_revision_name" {
  description = "The name of the latest revision"
  value       = azurerm_container_app.this.latest_revision_name
}

# latest_revision_fqdn - The fully qualified domain name
# The hostname for accessing the container app
output "latest_revision_fqdn" {
  description = "The FQDN of the latest revision"
  value       = azurerm_container_app.this.latest_revision_fqdn
}

# outbound_ip_addresses - List of outbound IP addresses
# Used for firewall rules when the app calls external services
output "outbound_ip_addresses" {
  description = "List of outbound IP addresses for the container app"
  value       = azurerm_container_app.this.outbound_ip_addresses
}

#------------------------------------------------------------------------------
# Identity Outputs
#------------------------------------------------------------------------------

# identity_principal_id - The principal ID of the managed identity
# Used for RBAC role assignments (Key Vault, ACR, etc.)
output "identity_principal_id" {
  description = "The principal ID of the system-assigned managed identity"
  value       = azurerm_container_app.this.identity[0].principal_id
}

# identity_tenant_id - The tenant ID of the managed identity
# Used for multi-tenant scenarios and authentication configuration
output "identity_tenant_id" {
  description = "The tenant ID of the system-assigned managed identity"
  value       = azurerm_container_app.this.identity[0].tenant_id
}

#------------------------------------------------------------------------------
# Ingress Outputs
#------------------------------------------------------------------------------

# ingress_fqdn - The FQDN of the container app ingress
# null if ingress is disabled
output "ingress_fqdn" {
  description = "The FQDN of the container app ingress"
  value       = var.ingress_enabled ? azurerm_container_app.this.latest_revision_fqdn : null
}

# application_url - The full HTTPS URL of the application
# Primary endpoint for accessing the application
# null if ingress is disabled
output "application_url" {
  description = "The full HTTPS URL of the application"
  value       = var.ingress_enabled ? "https://${azurerm_container_app.this.latest_revision_fqdn}" : null
}

#------------------------------------------------------------------------------
# Custom Domain Outputs
#------------------------------------------------------------------------------

# custom_domain_verification_id - Domain verification ID
# Required for custom domain ownership verification
output "custom_domain_verification_id" {
  description = "Domain verification ID for custom domain setup"
  value       = azurerm_container_app_environment.this.custom_domain_verification_id
}

# certificate_id - ID of the referenced certificate
# null if custom domain is not enabled
output "certificate_id" {
  description = "ID of the referenced certificate (if enabled)"
  value       = var.custom_domain_enabled ? data.azurerm_container_app_environment_certificate.this[0].id : null
}
