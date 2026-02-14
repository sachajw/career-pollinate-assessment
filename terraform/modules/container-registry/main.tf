#------------------------------------------------------------------------------
# Azure Container Registry Module - main.tf
#------------------------------------------------------------------------------
# This module creates an Azure Container Registry (ACR) for storing Docker
# container images. ACR provides private, Geo-replicated registry capabilities
# with features like content trust, retention policies, and private endpoints.
#
# Usage:
#   module "container_registry" {
#     source = "../../modules/container-registry"
#     name                = "acrmyappdev"
#     resource_group_name = "rg-myapp-dev"
#     location            = "eastus2"
#     sku                 = "Basic"
#     tags                = { Environment = "dev" }
#   }
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Container Registry
#------------------------------------------------------------------------------
# Azure Container Registry is a private Docker registry service. Images stored
# here are private and require authentication. We use Managed Identity for
# secure, passwordless authentication from Container Apps.
#------------------------------------------------------------------------------
resource "azurerm_container_registry" "this" {
  # Registry name - must be globally unique across all of Azure
  # 5-50 characters, lowercase alphanumeric only (no hyphens/underscores)
  name = var.name

  # Resource group and location
  resource_group_name = var.resource_group_name
  location            = var.location

  # SKU tier determines available features:
  # - Basic: Cost-optimized for dev/test, no premium features
  # - Standard: General-purpose production, standard throughput
  # - Premium: Geo-replication, private endpoints, retention policies
  sku = var.sku

  # Security: Admin user is disabled
  # We use Managed Identity for authentication instead of admin credentials
  # This is more secure as it eliminates static credentials
  admin_enabled = false

  # Network access configuration
  # true: Allow public internet access (suitable for dev)
  # false: Require private endpoints (recommended for production)
  public_network_access_enabled = var.public_network_access_enabled

  # Encryption with customer-managed keys (Premium SKU only)
  # When enabled, uses Key Vault for encryption key management
  dynamic "encryption" {
    for_each = var.encryption_enabled ? [1] : []
    content {
      enabled = true
    }
  }

  # Retention policy for untagged manifests (Premium SKU only)
  # Automatically cleans up old images to reduce storage costs
  # Only applies when retention_enabled is true
  dynamic "retention_policy" {
    for_each = var.sku == "Premium" ? [1] : []
    content {
      days    = var.retention_days
      enabled = var.retention_enabled
    }
  }

  # Trust policy for content signing (Premium SKU only)
  # Enables Docker Content Trust for image signing and verification
  dynamic "trust_policy" {
    for_each = var.sku == "Premium" && var.trust_policy_enabled ? [1] : []
    content {
      enabled = true
    }
  }

  # Resource tags for organization and cost management
  tags = var.tags
}

#------------------------------------------------------------------------------
# Scope Map (Optional)
#------------------------------------------------------------------------------
# Scope maps provide token-based authentication for granular access control
# to specific repositories. Useful for CI/CD pipelines or third-party access.
# Created only when create_scope_maps is true.
#------------------------------------------------------------------------------
resource "azurerm_container_registry_scope_map" "pull" {
  count = var.create_scope_maps ? 1 : 0

  name                    = "pull-scope"
  container_registry_name = azurerm_container_registry.this.name
  resource_group_name     = var.resource_group_name

  # Actions define what operations are allowed
  # These actions grant read-only access to all repositories
  actions = [
    "repositories/*/content/read",  # Pull images
    "repositories/*/metadata/read", # View tags and metadata
  ]
}

#------------------------------------------------------------------------------
# Diagnostic Settings (Optional)
#------------------------------------------------------------------------------
# Sends registry access logs and metrics to Log Analytics for monitoring
# and security auditing. Highly recommended for production environments.
#------------------------------------------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "acr" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "acr-diagnostics"
  target_resource_id         = azurerm_container_registry.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # Log categories for ACR:
  # - RepositoryEvents: Push, pull, delete operations on images
  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }

  # - LoginEvents: Authentication attempts (success/failure)
  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }

  # Metrics for performance monitoring
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
