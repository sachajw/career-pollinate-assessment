# Development Environment Outputs
# These outputs are displayed after terraform apply

# Resource Group
output "resource_group_name" {
  description = "Name of the resource group"
  value       = module.resource_group.name
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = module.resource_group.id
}

# Container App
output "container_app_url" {
  description = "Public URL of the container app"
  value       = module.container_app.application_url
}

output "container_app_fqdn" {
  description = "FQDN of the container app"
  value       = module.container_app.ingress_fqdn
}

output "container_app_identity_principal_id" {
  description = "Principal ID of the container app managed identity"
  value       = module.container_app.identity_principal_id
}

# Container Registry
output "container_registry_login_server" {
  description = "Login server URL for the container registry"
  value       = module.container_registry.login_server
}

output "container_registry_name" {
  description = "Name of the container registry"
  value       = module.container_registry.name
}

# Key Vault
output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = module.key_vault.vault_uri
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = module.key_vault.name
}

# Application Insights
output "app_insights_connection_string" {
  description = "Application Insights connection string"
  value       = module.observability.app_insights_connection_string
  sensitive   = true
}

output "app_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = module.observability.app_insights_instrumentation_key
  sensitive   = true
}

output "app_insights_app_id" {
  description = "Application Insights app ID"
  value       = module.observability.app_insights_app_id
}

# Log Analytics
output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = module.observability.log_analytics_workspace_id
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Quick start commands for deployment"
  value = <<-EOT
    # Login to Azure Container Registry
    az acr login --name ${module.container_registry.name}

    # Build and push Docker image
    docker build -t ${module.container_registry.login_server}/risk-scoring-api:latest ../../app
    docker push ${module.container_registry.login_server}/risk-scoring-api:latest

    # Set RiskShield API key in Key Vault
    az keyvault secret set --vault-name ${module.key_vault.name} --name RISKSHIELD-API-KEY --value "your-api-key-here"

    # Test the application
    curl https://${module.container_app.ingress_fqdn}/health

    # View logs
    az containerapp logs show --name ${module.container_app.name} --resource-group ${module.resource_group.name} --follow
  EOT
}
