# Production Environment Outputs

output "resource_group_name" {
  description = "Name of the resource group"
  value       = module.resource_group.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = module.resource_group.location
}

output "container_app_name" {
  description = "Name of the Container App"
  value       = module.container_app.name
}

output "container_app_url" {
  description = "URL of the Container App"
  value       = "https://${module.container_app.latest_revision_fqdn}"
}

output "container_registry_login_server" {
  description = "ACR login server URL"
  value       = module.container_registry.login_server
}

output "key_vault_uri" {
  description = "Key Vault URI"
  value       = module.key_vault.vault_uri
}

output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = module.observability.app_insights_connection_string
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID"
  value       = module.observability.log_analytics_workspace_id
}
