# Observability Module Outputs

# Log Analytics Outputs
output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.this.id
}

output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.this.name
}

output "log_analytics_primary_shared_key" {
  description = "The primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.this.primary_shared_key
  sensitive   = true
}

output "log_analytics_workspace_id_for_query" {
  description = "The workspace (customer) ID for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.this.workspace_id
}

# Application Insights Outputs
output "app_insights_id" {
  description = "The ID of the Application Insights instance"
  value       = azurerm_application_insights.this.id
}

output "app_insights_name" {
  description = "The name of the Application Insights instance"
  value       = azurerm_application_insights.this.name
}

output "app_insights_instrumentation_key" {
  description = "The instrumentation key for Application Insights"
  value       = azurerm_application_insights.this.instrumentation_key
  sensitive   = true
}

output "app_insights_connection_string" {
  description = "The connection string for Application Insights"
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "app_insights_app_id" {
  description = "The app ID for Application Insights"
  value       = azurerm_application_insights.this.app_id
}
