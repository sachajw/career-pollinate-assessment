# Key Vault Module Variables

variable "name" {
  description = "Name of the Key Vault (must be globally unique, 3-24 characters)"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.name))
    error_message = "Key Vault name must be 3-24 characters, start with letter, alphanumeric and hyphens only"
  }
}

variable "resource_group_name" {
  description = "Name of the resource group where Key Vault will be created"
  type        = string
}

variable "location" {
  description = "Azure region for the Key Vault"
  type        = string
}

variable "sku_name" {
  description = "SKU for Key Vault (standard or premium)"
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "SKU must be standard or premium"
  }
}

variable "soft_delete_retention_days" {
  description = "Number of days to retain deleted items (7-90 days)"
  type        = number
  default     = 90

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "Soft delete retention must be between 7 and 90 days"
  }
}

variable "purge_protection_enabled" {
  description = "Enable purge protection (prevents permanent deletion during retention period)"
  type        = bool
  default     = true # Always true for production
}

variable "public_network_access_enabled" {
  description = "Enable public network access to Key Vault"
  type        = bool
  default     = true # Set to false for production with private endpoint
}

variable "network_acls_enabled" {
  description = "Enable network ACLs for Key Vault"
  type        = bool
  default     = false # Enable in production
}

variable "network_acls_bypass" {
  description = "Which traffic can bypass network ACLs (AzureServices or None)"
  type        = string
  default     = "AzureServices"

  validation {
    condition     = contains(["AzureServices", "None"], var.network_acls_bypass)
    error_message = "Bypass must be AzureServices or None"
  }
}

variable "network_acls_default_action" {
  description = "Default action for network ACLs (Allow or Deny)"
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Allow", "Deny"], var.network_acls_default_action)
    error_message = "Default action must be Allow or Deny"
  }
}

variable "allowed_ip_ranges" {
  description = "List of allowed IP address ranges for Key Vault access"
  type        = list(string)
  default     = []
}

variable "allowed_subnet_ids" {
  description = "List of allowed subnet IDs for Key Vault access"
  type        = list(string)
  default     = []
}

variable "deployer_object_id" {
  description = "Object ID of the deployer (Terraform service principal or user) for RBAC"
  type        = string
  default     = null
}

variable "log_analytics_workspace_id" {
  description = "ID of Log Analytics workspace for diagnostics (optional)"
  type        = string
  default     = null
}

variable "secrets" {
  description = "Map of secrets to create in Key Vault (use with caution, prefer external secret injection)"
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "tags" {
  description = "Tags to apply to the Key Vault"
  type        = map(string)
  default     = {}
}
