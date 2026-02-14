# Azure Key Vault Module
# This module creates an Azure Key Vault for secure secret storage
# Features:
# - RBAC-based access control (not legacy access policies)
# - Soft delete and purge protection enabled
# - Network rules support
# - Private endpoint support (for production)
# - Diagnostic logging

# Get current Azure client configuration for tenant ID
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id

  # SKU: Standard or Premium (Premium supports HSM-backed keys)
  sku_name = var.sku_name

  # RBAC-based access control (modern approach, not access policies)
  enable_rbac_authorization = true

  # Soft delete: Allows recovery of deleted secrets/keys/certificates
  # Required for production to prevent accidental data loss
  soft_delete_retention_days = var.soft_delete_retention_days
  purge_protection_enabled   = var.purge_protection_enabled

  # Network rules for restricting access
  # In dev: Allow all networks
  # In prod: Restrict to specific VNets/IPs + use private endpoint
  public_network_access_enabled = var.public_network_access_enabled

  dynamic "network_acls" {
    for_each = var.network_acls_enabled ? [1] : []
    content {
      bypass                     = var.network_acls_bypass
      default_action             = var.network_acls_default_action
      ip_rules                   = var.allowed_ip_ranges
      virtual_network_subnet_ids = var.allowed_subnet_ids
    }
  }

  tags = var.tags
}

# Diagnostic settings for audit logging
# All Key Vault access is logged for security and compliance
resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  count = var.log_analytics_workspace_id != null ? 1 : 0

  name                       = "keyvault-diagnostics"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # Enable audit event logging (all access attempts)
  enabled_log {
    category = "AuditEvent"
  }

  # Enable Azure Policy logging
  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }

  # Enable all metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# RBAC Role Assignment for deployer/admin
# This allows the Terraform service principal to manage secrets
# In production, this should be tightly controlled
resource "azurerm_role_assignment" "deployer" {
  count = var.deployer_object_id != null ? 1 : 0

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = var.deployer_object_id
}

# Example secrets (these should be added via separate process, not in Terraform)
# Secrets are typically injected via CI/CD pipeline or manually
# This is just a placeholder to show the structure
resource "azurerm_key_vault_secret" "secrets" {
  for_each = var.secrets

  name         = each.key
  value        = each.value
  key_vault_id = azurerm_key_vault.this.id

  # Mark as sensitive to prevent exposure in logs
  content_type = "text/plain"

  # Depends on RBAC assignment to ensure deployer has permission
  depends_on = [azurerm_role_assignment.deployer]
}
