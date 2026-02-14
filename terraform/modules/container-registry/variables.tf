# Container Registry Module Variables

variable "name" {
  description = "Name of the container registry (must be globally unique, alphanumeric only)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{5,50}$", var.name))
    error_message = "ACR name must be 5-50 characters, lowercase alphanumeric only"
  }
}

variable "resource_group_name" {
  description = "Name of the resource group where ACR will be created"
  type        = string
}

variable "location" {
  description = "Azure region for the container registry"
  type        = string
}

variable "sku" {
  description = "SKU tier for ACR (Basic, Standard, or Premium)"
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "SKU must be Basic, Standard, or Premium"
  }
}

variable "public_network_access_enabled" {
  description = "Whether to enable public network access to ACR"
  type        = bool
  default     = true # Set to false for production with private endpoints
}

variable "encryption_enabled" {
  description = "Enable encryption with customer-managed keys (Premium SKU only)"
  type        = bool
  default     = false
}

variable "retention_enabled" {
  description = "Enable retention policy for untagged manifests (Premium SKU only)"
  type        = bool
  default     = false
}

variable "retention_days" {
  description = "Number of days to retain untagged manifests"
  type        = number
  default     = 7

  validation {
    condition     = var.retention_days >= 0 && var.retention_days <= 365
    error_message = "Retention days must be between 0 and 365"
  }
}

variable "trust_policy_enabled" {
  description = "Enable content trust policy (Premium SKU only)"
  type        = bool
  default     = false
}

variable "create_scope_maps" {
  description = "Create scope maps for token-based authentication"
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  description = "ID of Log Analytics workspace for diagnostics (optional)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to the container registry"
  type        = map(string)
  default     = {}
}
