# Container App Module Outputs

# Environment Outputs
output "environment_id" {
  description = "The ID of the container app environment"
  value       = azurerm_container_app_environment.this.id
}

output "environment_name" {
  description = "The name of the container app environment"
  value       = azurerm_container_app_environment.this.name
}

output "environment_default_domain" {
  description = "The default domain of the container app environment"
  value       = azurerm_container_app_environment.this.default_domain
}

output "environment_static_ip" {
  description = "The static IP address of the container app environment"
  value       = azurerm_container_app_environment.this.static_ip_address
}

# Container App Outputs
output "id" {
  description = "The ID of the container app"
  value       = azurerm_container_app.this.id
}

output "name" {
  description = "The name of the container app"
  value       = azurerm_container_app.this.name
}

output "latest_revision_name" {
  description = "The name of the latest revision"
  value       = azurerm_container_app.this.latest_revision_name
}

output "latest_revision_fqdn" {
  description = "The FQDN of the latest revision"
  value       = azurerm_container_app.this.latest_revision_fqdn
}

output "outbound_ip_addresses" {
  description = "List of outbound IP addresses for the container app"
  value       = azurerm_container_app.this.outbound_ip_addresses
}

# Identity Outputs
output "identity_principal_id" {
  description = "The principal ID of the system-assigned managed identity"
  value       = azurerm_container_app.this.identity[0].principal_id
}

output "identity_tenant_id" {
  description = "The tenant ID of the system-assigned managed identity"
  value       = azurerm_container_app.this.identity[0].tenant_id
}

# Ingress Outputs
output "ingress_fqdn" {
  description = "The FQDN of the container app ingress"
  value       = var.ingress_enabled ? azurerm_container_app.this.latest_revision_fqdn : null
}

output "application_url" {
  description = "The full HTTPS URL of the application"
  value       = var.ingress_enabled ? "https://${azurerm_container_app.this.latest_revision_fqdn}" : null
}
