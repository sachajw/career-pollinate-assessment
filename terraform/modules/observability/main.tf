#------------------------------------------------------------------------------
# Azure Observability Module - main.tf
#------------------------------------------------------------------------------
# This module creates a complete observability stack for monitoring Azure
# applications. It includes:
# - Log Analytics Workspace: Centralized log aggregation and querying
# - Application Insights: Application Performance Monitoring (APM)
# - Availability Tests: Synthetic monitoring for endpoint health
#
# These resources are tightly coupled as Application Insights requires Log
# Analytics in workspace-based mode for enhanced capabilities.
#
# Usage:
#   module "observability" {
#     source = "../../modules/observability"
#     resource_group_name      = "rg-myapp-dev"
#     location                 = "eastus2"
#     log_analytics_name       = "log-myapp-dev"
#     app_insights_name        = "appi-myapp-dev"
#     tags                     = { Environment = "dev" }
#   }
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Log Analytics Workspace
#------------------------------------------------------------------------------
# Log Analytics is a centralized logging service that collects and analyzes
# telemetry from Azure resources. It provides:
# - Log queries with KQL (Kusto Query Language)
# - Alerting capabilities
# - Integration with Azure Monitor
# - Long-term log retention
#------------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "this" {
  name                = var.log_analytics_name
  resource_group_name = var.resource_group_name
  location            = var.location

  # SKU: Pricing tier for the workspace
  # PerGB2018: Pay per GB of data ingested (current standard)
  # Free: Limited features, 7-day retention, 500MB/day limit
  sku = var.log_analytics_sku

  # Data retention period in days
  # - Dev: 30 days to minimize cost
  # - Prod: 90-365 days for compliance and troubleshooting
  # Free tier is limited to 7 days
  retention_in_days = var.log_analytics_retention_days

  # Daily ingestion cap in GB
  # Prevents unexpected cost spikes from excessive logging
  # Set to null for unlimited ingestion (use with caution in production)
  daily_quota_gb = var.log_analytics_daily_quota_gb

  # Network access for data ingestion and queries
  # true: Allow from public internet (suitable for dev)
  # false: Require private link (recommended for production)
  internet_ingestion_enabled = var.internet_ingestion_enabled
  internet_query_enabled     = var.internet_query_enabled

  # Resource tags for organization and cost management
  tags = var.tags
}

#------------------------------------------------------------------------------
# Application Insights
#------------------------------------------------------------------------------
# Application Insights is an APM (Application Performance Monitoring) service
# that provides:
# - Request tracking and latency metrics
# - Exception and error logging
# - Dependency tracking (database, HTTP calls)
# - Custom telemetry and events
# - Live metrics and dashboards
# - Distributed tracing
#
# Uses workspace-based mode (modern approach) which stores data in the
# Log Analytics workspace created above.
#------------------------------------------------------------------------------
resource "azurerm_application_insights" "this" {
  name                = var.app_insights_name
  resource_group_name = var.resource_group_name
  location            = var.location

  # Application type affects default telemetry collection
  # - web: Web applications (REST APIs, web apps)
  # - other: General purpose
  # - java: Java applications with JVM metrics
  # - Node.JS: Node.js applications
  application_type = var.application_type

  # Workspace-based mode (recommended)
  # Links Application Insights to Log Analytics workspace
  # Benefits: Unified queries, longer retention, better integration
  workspace_id = azurerm_log_analytics_workspace.this.id

  # Sampling percentage (1-100)
  # Controls how much telemetry is retained
  # - 100: Capture all telemetry (recommended for dev)
  # - 20-50: Sample a portion (recommended for high-traffic prod)
  # Lower values reduce cost but may miss infrequent issues
  sampling_percentage = var.sampling_percentage

  # Retention override for Application Insights data
  # null: Use workspace retention setting
  # Set explicitly to override workspace default
  retention_in_days = var.app_insights_retention_days

  # Daily data cap in GB
  # Prevents runaway telemetry costs
  # null: No cap (bill scales with usage)
  daily_data_cap_in_gb = var.app_insights_daily_cap_gb

  # IP masking behavior
  # true: Show full IP addresses (easier debugging in dev)
  # false: Mask last octet (privacy in production)
  disable_ip_masking = var.disable_ip_masking

  # Authentication mode
  # true: Disable local authentication (require AAD/RBAC)
  # false: Allow API key authentication (easier for dev)
  local_authentication_disabled = var.local_authentication_disabled

  # Network access for telemetry ingestion and queries
  # true: Allow from public internet (suitable for dev)
  # false: Require private link (recommended for production)
  internet_ingestion_enabled = var.internet_ingestion_enabled
  internet_query_enabled     = var.internet_query_enabled

  # Resource tags for organization and cost management
  tags = var.tags
}

#------------------------------------------------------------------------------
# Availability Test (Optional)
#------------------------------------------------------------------------------
# Synthetic monitoring that periodically checks endpoint availability.
# Creates web tests that run from multiple Azure regions to verify:
# - Endpoint is reachable
# - Response time is acceptable
# - SSL certificate is valid
# - Response status code is expected
#
# Useful for proactive monitoring and alerting on availability issues.
#------------------------------------------------------------------------------
resource "azurerm_application_insights_standard_web_test" "health" {
  count = var.create_availability_test ? 1 : 0

  name                    = "${var.app_insights_name}-health-test"
  resource_group_name     = var.resource_group_name
  location                = var.location
  application_insights_id = azurerm_application_insights.this.id

  # Test frequency in seconds
  # Options: 300 (5 min), 600 (10 min), 900 (15 min)
  frequency = 300

  # Test timeout in seconds
  # Fail if no response within this time
  timeout = 120

  # Enable/disable the test
  enabled = true

  # Geographic locations to run tests from
  # Tests run simultaneously from all locations
  # Use multiple locations for redundancy
  geo_locations = var.test_locations

  # HTTP request configuration
  request {
    # URL to test (should be health check endpoint)
    url = var.health_check_url

    # Optional HTTP headers
    dynamic "header" {
      for_each = var.health_check_headers
      content {
        name  = header.key
        value = header.value
      }
    }
  }

  # Validation rules for the response
  validation_rules {
    # Expected HTTP status code (200 = OK)
    expected_status_code = 200

    # SSL certificate validation
    ssl_check_enabled           = true
    ssl_cert_remaining_lifetime = 7 # Alert if cert expires within 7 days
  }

  # Resource tags for organization and cost management
  tags = var.tags
}
