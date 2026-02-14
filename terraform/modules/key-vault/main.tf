#------------------------------------------------------------------------------
# Azure Key Vault Module - main.tf
#------------------------------------------------------------------------------
# This module creates an Azure Key Vault for secure storage of secrets, keys,
# and certificates. Key Vault provides centralized secret management with
# RBAC-based access control, audit logging, and data protection features.
#
# Usage:
#   module "key_vault" {
#     source = "../../modules/key-vault"
#     name                = "kv-myapp-dev"
#     resource_group_name = "rg-myapp-dev"
#     location            = "eastus2"
#     tags                = { Environment = "dev" }
#   }
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Data Sources
#------------------------------------------------------------------------------

# Get current Azure client configuration
# Used to retrieve the tenant ID for Key Vault access configuration
data "azurerm_client_config" "current" {}

#------------------------------------------------------------------------------
# Key Vault
#------------------------------------------------------------------------------
# Azure Key Vault is a cloud service for securely storing and accessing secrets.
# This configuration uses RBAC authorization (modern approach) instead of
# access policies (legacy approach) for better security management.
#------------------------------------------------------------------------------
resource "azurerm_key_vault" "this" {
  # Key Vault name - must be globally unique, 3-24 characters
  # Must start with letter, contain only lowercase alphanumeric and hyphens
  name = var.name

  # Resource group and location
  resource_group_name = var.resource_group_name
  location            = var.location

  # Azure AD tenant ID for access control
  tenant_id = data.azurerm_client_config.current.tenant_id

  # SKU tier:
  # - standard: Software-protected keys and secrets
  # - premium: HSM-backed keys for enhanced security (required for certain compliance)
  sku_name = var.sku_name

  # RBAC Authorization (modern approach)
  # When true, uses Azure RBAC for access control instead of access policies
  # This is the recommended approach for new deployments
  enable_rbac_authorization = true

  # Soft Delete: Allows recovery of deleted secrets/keys/certificates
  # Retention period (7-90 days) determines how long deleted items are recoverable
  # This is a data protection feature - always enable in production
  soft_delete_retention_days = var.soft_delete_retention_days

  # Purge Protection: Prevents permanent deletion during retention period
  # Even with soft delete, items can be purged (permanently deleted) without this
  # Enable in production to prevent accidental or malicious data loss
  purge_protection_enabled = var.purge_protection_enabled

  # Network access configuration
  # true: Allow public internet access (suitable for dev)
  # false: Require private endpoints (recommended for production)
  public_network_access_enabled = var.public_network_access_enabled

  # Network ACLs for fine-grained access control
  # When enabled, restricts access to specific IP ranges and subnets
  dynamic "network_acls" {
    for_each = var.network_acls_enabled ? [1] : []
    content {
      # Which services can bypass network rules
      # AzureServices: Allow trusted Azure services (recommended)
      # None: No bypass, all access must be explicit
      bypass = var.network_acls_bypass

      # Default action when no rule matches
      # Deny: Block all access not explicitly allowed (recommended for production)
      # Allow: Allow all access not explicitly denied
      default_action = var.network_acls_default_action

      # Allowed IP addresses/ranges (CIDR notation)
      ip_rules = var.allowed_ip_ranges

      # Allowed virtual network subnets (requires service endpoint)
      virtual_network_subnet_ids = var.allowed_subnet_ids
    }
  }

  # Resource tags for organization and cost management
  tags = var.tags

  # Lifecycle management for Key Vault protection
  lifecycle {
    # Prevent accidental destruction of Key Vault (contains sensitive secrets)
    # Uncomment for production environments to prevent terraform destroy
    # prevent_destroy = true

    # Preconditions: Validate configuration before apply
    precondition {
      condition     = length(var.name) >= 3 && length(var.name) <= 24
      error_message = "Key Vault name must be between 3 and 24 characters."
    }

    precondition {
      condition     = can(regex("^[a-z][a-z0-9-]{2,23}$", var.name))
      error_message = "Key Vault name must start with a letter, contain only lowercase alphanumeric characters or hyphens, and be 3-24 characters."
    }

    precondition {
      condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
      error_message = "Soft delete retention must be between 7 and 90 days."
    }
  }
}

#------------------------------------------------------------------------------
# Diagnostic Settings (Optional)
#------------------------------------------------------------------------------
# Sends Key Vault audit logs to Log Analytics for security monitoring
# All access attempts (successful and failed) are logged for compliance
#------------------------------------------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "keyvault-diagnostics"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # Audit Event logging - records all Key Vault access attempts
  # Critical for security compliance and forensics
  enabled_log {
    category = "AuditEvent"
  }

  # Azure Policy evaluation details
  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }

  # Metrics for performance monitoring
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

#------------------------------------------------------------------------------
# RBAC Role Assignment for Deployer/Admin (Optional)
#------------------------------------------------------------------------------
# Grants Key Vault Administrator role to the deployer (Terraform service
# principal or user). This allows Terraform to manage secrets in the vault.
# In production, this should be tightly controlled and follow least privilege.
#------------------------------------------------------------------------------
resource "azurerm_role_assignment" "deployer" {
  count = var.deployer_object_id != null ? 1 : 0

  # Scope: The Key Vault resource
  scope = azurerm_key_vault.this.id

  # Role: Key Vault Administrator
  # Grants full control over secrets, keys, and certificates
  # Consider using more restricted roles for production (e.g., Key Vault Secrets Officer)
  role_definition_name = "Key Vault Administrator"

  # Principal: The deployer's Azure AD object ID
  principal_id = var.deployer_object_id
}

#------------------------------------------------------------------------------
# Secrets (Optional)
#------------------------------------------------------------------------------
# Creates secrets in Key Vault from the provided map.
# WARNING: While the values are protected in Terraform state, prefer
# injecting secrets via CI/CD pipeline or manual creation for production.
# This is primarily for non-sensitive configuration and development.
#------------------------------------------------------------------------------
resource "azurerm_key_vault_secret" "secrets" {
  for_each = var.secrets

  # Secret name (becomes the identifier in Key Vault)
  name = each.key

  # Secret value (protected in state, not shown in logs)
  value = each.value

  # Reference to the Key Vault
  key_vault_id = azurerm_key_vault.this.id

  # Content type for metadata
  content_type = "text/plain"

  # Ensure RBAC assignment is complete before creating secrets
  depends_on = [azurerm_role_assignment.deployer]

  # Lifecycle: Create new before destroying old during updates
  lifecycle {
    create_before_destroy = true
  }
}
