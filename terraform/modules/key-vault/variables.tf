#------------------------------------------------------------------------------
# Azure Key Vault Module - variables.tf
#------------------------------------------------------------------------------
# Input variable definitions for the Azure Key Vault module.
# Key Vault provides secure storage for secrets, keys, and certificates
# with features like RBAC access control, soft delete, and audit logging.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Required Variables
#------------------------------------------------------------------------------

# name - Globally unique name for the Key Vault
# Must be 3-24 characters, start with letter, alphanumeric and hyphens only
# Example: kv-riskscoring-dev, kv-myapp-prod
variable "name" {
  description = "Name of the Key Vault (must be globally unique, 3-24 characters)"
  type        = string

  # Validation: Ensure name meets Azure naming requirements
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.name))
    error_message = "Key Vault name must be 3-24 characters, start with letter, alphanumeric and hyphens only"
  }
}

# resource_group_name - The resource group where Key Vault will be created
# Typically created by the resource-group module
variable "resource_group_name" {
  description = "Name of the resource group where Key Vault will be created"
  type        = string
}

# location - Azure region for the Key Vault
# Should match the resource group location
variable "location" {
  description = "Azure region for the Key Vault"
  type        = string
}

#------------------------------------------------------------------------------
# SKU Configuration
#------------------------------------------------------------------------------

# sku_name - The pricing tier for Key Vault
# standard: Software-protected keys and secrets
# premium: HSM-backed keys (required for certain compliance requirements)
variable "sku_name" {
  description = "SKU for Key Vault (standard or premium)"
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "SKU must be standard or premium"
  }
}

#------------------------------------------------------------------------------
# Data Protection Configuration
#------------------------------------------------------------------------------

# soft_delete_retention_days - How long to retain deleted items
# Allows recovery of accidentally deleted secrets/keys/certificates
# Must be between 7-90 days
variable "soft_delete_retention_days" {
  description = "Number of days to retain deleted items (7-90 days)"
  type        = number
  default     = 90

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "Soft delete retention must be between 7 and 90 days"
  }
}

# purge_protection_enabled - Prevent permanent deletion during retention
# When true, deleted items cannot be purged until retention period expires
# Recommended for production to prevent data loss
variable "purge_protection_enabled" {
  description = "Enable purge protection (prevents permanent deletion during retention period)"
  type        = bool
  default     = true
}

#------------------------------------------------------------------------------
# Network Configuration
#------------------------------------------------------------------------------

# public_network_access_enabled - Whether to allow public internet access
# true: Allow public access (suitable for dev)
# false: Require private endpoints (recommended for production)
variable "public_network_access_enabled" {
  description = "Enable public network access to Key Vault"
  type        = bool
  default     = true
}

# network_acls_enabled - Whether to enable network ACLs
# When true, restricts access to specific IP ranges and subnets
variable "network_acls_enabled" {
  description = "Enable network ACLs for Key Vault"
  type        = bool
  default     = false
}

# network_acls_bypass - Which services can bypass network rules
# AzureServices: Allow trusted Azure services
# None: No bypass, all access must be explicit
variable "network_acls_bypass" {
  description = "Which traffic can bypass network ACLs (AzureServices or None)"
  type        = string
  default     = "AzureServices"

  validation {
    condition     = contains(["AzureServices", "None"], var.network_acls_bypass)
    error_message = "Bypass must be AzureServices or None"
  }
}

# network_acls_default_action - Default action for unmatched requests
# Deny: Block all not explicitly allowed (recommended for production)
# Allow: Allow all not explicitly denied
variable "network_acls_default_action" {
  description = "Default action for network ACLs (Allow or Deny)"
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Allow", "Deny"], var.network_acls_default_action)
    error_message = "Default action must be Allow or Deny"
  }
}

# allowed_ip_ranges - IP addresses/ranges allowed to access Key Vault
# Use CIDR notation (e.g., "10.0.0.0/24", "192.168.1.1/32")
variable "allowed_ip_ranges" {
  description = "List of allowed IP address ranges for Key Vault access"
  type        = list(string)
  default     = []
}

# allowed_subnet_ids - Subnet IDs allowed to access Key Vault
# Requires Microsoft.KeyVault service endpoint enabled on the subnet
variable "allowed_subnet_ids" {
  description = "List of allowed subnet IDs for Key Vault access"
  type        = list(string)
  default     = []
}

#------------------------------------------------------------------------------
# Access Configuration
#------------------------------------------------------------------------------

# deployer_object_id - Azure AD object ID for RBAC assignment
# Grant Key Vault Administrator role to the deployer (Terraform SP or user)
# Set to null to skip deployer role assignment
variable "deployer_object_id" {
  description = "Object ID of the deployer (Terraform service principal or user) for RBAC"
  type        = string
  default     = null
}

#------------------------------------------------------------------------------
# Diagnostic Settings
#------------------------------------------------------------------------------

# enable_diagnostics - Enable diagnostic logging to Log Analytics
# Recommended for production to audit all Key Vault access
variable "enable_diagnostics" {
  description = "Enable diagnostic settings for the Key Vault"
  type        = bool
  default     = true
}

# log_analytics_workspace_id - Workspace for diagnostic logs
# Required when enable_diagnostics is true
variable "log_analytics_workspace_id" {
  description = "ID of Log Analytics workspace for diagnostics (required if enable_diagnostics = true)"
  type        = string
  default     = ""
}

#------------------------------------------------------------------------------
# Secrets Configuration
#------------------------------------------------------------------------------

# secrets - Map of secrets to create in Key Vault
# WARNING: Prefer injecting secrets via CI/CD pipeline or manual creation
# Note: Not marked sensitive to allow for_each, but values are protected in state
variable "secrets" {
  description = "Map of secrets to create in Key Vault (use with caution, prefer external secret injection). Note: Not marked sensitive to allow for_each, but values are still protected in state."
  type        = map(string)
  default     = {}
  # NOTE: sensitive = true cannot be used with for_each in Terraform
  # The secret values are still protected in Terraform state
}

#------------------------------------------------------------------------------
# Optional Variables
#------------------------------------------------------------------------------

# tags - Resource tags for organization and cost management
variable "tags" {
  description = "Tags to apply to the Key Vault"
  type        = map(string)
  default     = {}
}
