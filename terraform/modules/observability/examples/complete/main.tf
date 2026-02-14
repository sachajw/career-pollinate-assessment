# Observability Module - Complete Example
# This example demonstrates all configuration options

# First, create a resource group
module "resource_group" {
  source = "../../resource-group"

  name     = "rg-obs-example"
  location = "eastus2"

  tags = {
    Environment = "dev"
    Project     = "terraform-modules"
  }
}

# Create the Observability Stack
module "observability" {
  source = "../.."

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location

  # Log Analytics Configuration
  log_analytics_name           = "log-obs-example"
  log_analytics_sku            = "PerGB2018"
  log_analytics_retention_days = 30
  log_analytics_daily_quota_gb = 5 # Cap at 5GB/day

  # Application Insights Configuration
  app_insights_name         = "appi-obs-example"
  application_type          = "web" # Options: web, other, java, Node.JS
  sampling_percentage       = 100   # 100% for dev, 20-50% for production
  app_insights_daily_cap_gb = 2     # Cap at 2GB/day

  # Security Settings
  disable_ip_masking            = true  # Show full IPs for debugging (false for production)
  local_authentication_disabled = false # Allow API key auth for dev
  internet_ingestion_enabled    = true  # Disable for production with private link
  internet_query_enabled        = true  # Disable for production with private link

  # Availability Test (optional)
  create_availability_test = true
  health_check_url         = "https://example.com/health"
  test_locations = [
    "us-va-ash-azr", # US East
    "us-ca-sjc-azr", # US West
  ]

  tags = {
    Environment = "dev"
    Project     = "terraform-modules"
    ManagedBy   = "terraform"
  }
}

# Outputs
output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace"
  value       = module.observability.log_analytics_workspace_id
}

output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics workspace"
  value       = module.observability.log_analytics_workspace_name
}

output "app_insights_id" {
  description = "The ID of Application Insights"
  value       = module.observability.app_insights_id
}

output "app_insights_name" {
  description = "The name of Application Insights"
  value       = module.observability.app_insights_name
}

output "app_insights_connection_string" {
  description = "The connection string for Application Insights"
  value       = module.observability.app_insights_connection_string
  sensitive   = true
}
