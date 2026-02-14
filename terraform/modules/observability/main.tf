# Observability Module
# This module creates Log Analytics workspace and Application Insights
# These are tightly coupled as App Insights requires Log Analytics in workspace mode

# Log Analytics Workspace
# Centralized logging and query platform for all Azure resources
resource "azurerm_log_analytics_workspace" "this" {
  name                = var.log_analytics_name
  resource_group_name = var.resource_group_name
  location            = var.location

  # SKU: PerGB2018 is the current standard (pay per GB ingested)
  sku = var.log_analytics_sku

  # Data retention in days (31-730 days, or 30 days for free tier)
  # Dev: 30 days to minimize cost
  # Prod: 90-365 days for compliance
  retention_in_days = var.log_analytics_retention_days

  # Daily cap to prevent cost overruns (GB per day)
  # Set to null for unlimited (use with caution)
  daily_quota_gb = var.log_analytics_daily_quota_gb

  # Internet ingestion/query enabled for dev
  # Disable in production with private link
  internet_ingestion_enabled = var.internet_ingestion_enabled
  internet_query_enabled     = var.internet_query_enabled

  tags = var.tags
}

# Application Insights
# APM and telemetry for the application
# Uses workspace-based model (new standard, not classic)
resource "azurerm_application_insights" "this" {
  name                = var.app_insights_name
  resource_group_name = var.resource_group_name
  location            = var.location

  # Application type: web, other, java, nodejs, etc.
  # "web" is appropriate for FastAPI REST API
  application_type = var.application_type

  # Workspace-based (modern approach, better integration)
  workspace_id = azurerm_log_analytics_workspace.this.id

  # Sampling percentage (1-100)
  # 100 = no sampling (capture all telemetry)
  # Lower values reduce cost but may miss issues
  # Dev: 100% for full visibility
  # Prod: 20-50% to balance cost and coverage
  sampling_percentage = var.sampling_percentage

  # Retention in days (override workspace default)
  # null = use workspace retention
  retention_in_days = var.app_insights_retention_days

  # Daily data cap in GB
  # null = no cap (bill scales with usage)
  daily_data_cap_in_gb = var.app_insights_daily_cap_gb

  # Disable IP masking for better debugging (dev only)
  # Enable in production for privacy
  disable_ip_masking = var.disable_ip_masking

  # Local authentication disabled (use AAD/RBAC instead)
  local_authentication_disabled = var.local_authentication_disabled

  # Internet ingestion/query (disable for prod with private link)
  internet_ingestion_enabled = var.internet_ingestion_enabled
  internet_query_enabled     = var.internet_query_enabled

  tags = var.tags
}

# Application Insights Web Test (optional)
# Synthetic monitoring to test endpoint availability
resource "azurerm_application_insights_standard_web_test" "health" {
  count = var.create_availability_test ? 1 : 0

  name                    = "${var.app_insights_name}-health-test"
  resource_group_name     = var.resource_group_name
  location                = var.location
  application_insights_id = azurerm_application_insights.this.id

  # Test frequency in seconds (300, 600, 900)
  frequency = 300

  # Test timeout in seconds
  timeout = 120

  # Enabled flag
  enabled = true

  # Geo locations to test from
  geo_locations = var.test_locations

  # HTTP request configuration
  request {
    url = var.health_check_url

    # Optional headers
    dynamic "header" {
      for_each = var.health_check_headers
      content {
        name  = header.key
        value = header.value
      }
    }
  }

  # Validation rules
  validation_rules {
    expected_status_code = 200
    ssl_check_enabled    = true
    ssl_cert_remaining_lifetime = 7
  }

  tags = var.tags
}
