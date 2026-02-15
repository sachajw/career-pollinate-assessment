#------------------------------------------------------------------------------
# Azure DevOps Module Outputs
#------------------------------------------------------------------------------

output "github_service_connection_id" {
  description = "GitHub service connection ID"
  value       = azuredevops_serviceendpoint_github.github.id
}

output "azurerm_service_connection_id" {
  description = "Azure RM service connection ID"
  value       = azuredevops_serviceendpoint_azurerm.azurerm.id
}

output "acr_service_connection_id" {
  description = "Azure Container Registry service connection ID"
  value       = azuredevops_serviceendpoint_azurerm.acr.id
}

output "infrastructure_variable_group_id" {
  description = "Infrastructure variable group ID"
  value       = azuredevops_variable_group.infrastructure.id
}

output "secrets_variable_group_id" {
  description = "Secrets variable group ID"
  value       = azuredevops_variable_group.secrets.id
}

output "build_definition_id" {
  description = "Build definition ID"
  value       = azuredevops_build_definition.pipeline.id
}

output "build_definition_url" {
  description = "URL to the build pipeline"
  value       = "https://dev.azure.com/${var.project_id}/_build?definitionId=${azuredevops_build_definition.pipeline.id}"
}
