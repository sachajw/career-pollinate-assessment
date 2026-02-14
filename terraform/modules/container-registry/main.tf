# Azure Container Registry Module
# This module creates an Azure Container Registry (ACR) for storing Docker images
# Features:
# - Admin user disabled (use Managed Identity instead)
# - Configurable SKU (Basic for dev, Premium for prod with geo-replication)
# - Public network access configurable
# - Retention policy for untagged manifests
# - Trust policy and content trust support

resource "azurerm_container_registry" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku

  # Security: Admin user disabled, use Managed Identity for access
  admin_enabled = false

  # Network access configuration
  public_network_access_enabled = var.public_network_access_enabled

  # Encryption configuration (customer-managed keys for Premium SKU)
  dynamic "encryption" {
    for_each = var.encryption_enabled ? [1] : []
    content {
      enabled = true
    }
  }

  # Retention policy for untagged manifests (Premium SKU only)
  dynamic "retention_policy" {
    for_each = var.sku == "Premium" ? [1] : []
    content {
      days    = var.retention_days
      enabled = var.retention_enabled
    }
  }

  # Trust policy (Premium SKU only)
  dynamic "trust_policy" {
    for_each = var.sku == "Premium" && var.trust_policy_enabled ? [1] : []
    content {
      enabled = true
    }
  }

  tags = var.tags
}

# Geo-replication for Premium SKU (prod only, out of scope for dev)
# This is included for completeness but not used in dev environment
resource "azurerm_container_registry_scope_map" "pull" {
  count                   = var.create_scope_maps ? 1 : 0
  name                    = "pull-scope"
  container_registry_name = azurerm_container_registry.this.name
  resource_group_name     = var.resource_group_name

  actions = [
    "repositories/*/content/read",
    "repositories/*/metadata/read",
  ]
}

# Diagnostic settings for monitoring
resource "azurerm_monitor_diagnostic_setting" "acr" {
  count = var.log_analytics_workspace_id != null ? 1 : 0

  name                       = "acr-diagnostics"
  target_resource_id         = azurerm_container_registry.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # Enable all log categories
  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }

  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }

  # Enable all metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
