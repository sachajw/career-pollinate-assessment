#------------------------------------------------------------------------------
# Azure Observability Module - outputs.tf
#------------------------------------------------------------------------------
# Output definitions for the observability module.
# These outputs are used by dependent modules (Container Apps, applications)
# and for integration with monitoring and alerting systems.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Log Analytics Outputs
#------------------------------------------------------------------------------

# log_analytics_workspace_id - The Azure Resource Manager ID
# Used for diagnostic settings and resource linking
output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.this.id
}

# log_analytics_workspace_name - The name of the workspace
# Used for display and scripting purposes
output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.this.name
}

# log_analytics_primary_shared_key - The primary access key
# Used for log ingestion in some scenarios
# Marked sensitive to prevent accidental exposure
output "log_analytics_primary_shared_key" {
  description = "The primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.this.primary_shared_key
  sensitive   = true
}

# log_analytics_workspace_id_for_query - The workspace/customer ID
# Used for KQL queries and API access
# Different from the Resource Manager ID
output "log_analytics_workspace_id_for_query" {
  description = "The workspace (customer) ID for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.this.workspace_id
}

#------------------------------------------------------------------------------
# Application Insights Outputs
#------------------------------------------------------------------------------

# app_insights_id - The Azure Resource Manager ID
# Used for resource linking and ARM templates
output "app_insights_id" {
  description = "The ID of the Application Insights instance"
  value       = azurerm_application_insights.this.id
}

# app_insights_name - The name of the instance
# Used for display and scripting purposes
output "app_insights_name" {
  description = "The name of the Application Insights instance"
  value       = azurerm_application_insights.this.name
}

# app_insights_instrumentation_key - The instrumentation key
# Legacy identifier for Application Insights
# Prefer connection_string for new applications
# Marked sensitive to prevent accidental exposure
output "app_insights_instrumentation_key" {
  description = "The instrumentation key for Application Insights"
  value       = azurerm_application_insights.this.instrumentation_key
  sensitive   = true
}

# app_insights_connection_string - The connection string
# Modern way to configure Application Insights SDK
# Contains all endpoint information needed for telemetry
# Marked sensitive to prevent accidental exposure
output "app_insights_connection_string" {
  description = "The connection string for Application Insights"
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

# app_insights_app_id - The application ID
# Used for API access and cross-resource queries
output "app_insights_app_id" {
  description = "The app ID for Application Insights"
  value       = azurerm_application_insights.this.app_id
}
