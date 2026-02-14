#------------------------------------------------------------------------------
# Azure Container Registry Module - variables.tf
#------------------------------------------------------------------------------
# Input variable definitions for the Azure Container Registry (ACR) module.
# ACR provides private Docker container registry capabilities with features
# like geo-replication, content trust, and private endpoints.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Required Variables
#------------------------------------------------------------------------------

# name - Globally unique name for the container registry
# Must be 5-50 characters, lowercase alphanumeric only
# Example: acrmyappdev, acrriskscoringprod
variable "name" {
  description = "Name of the container registry (must be globally unique, 5-50 characters, lowercase alphanumeric only)"
  type        = string

  # Validation: Ensure name meets Azure naming requirements
  validation {
    condition     = can(regex("^[a-z0-9]{5,50}$", var.name))
    error_message = "ACR name must be 5-50 characters, lowercase alphanumeric only (no hyphens or underscores)"
  }
}

# resource_group_name - The resource group where ACR will be created
# Typically created by the resource-group module
variable "resource_group_name" {
  description = "Name of the resource group where ACR will be created"
  type        = string
}

# location - Azure region for the container registry
# Should match the resource group location
variable "location" {
  description = "Azure region for the container registry"
  type        = string
}

#------------------------------------------------------------------------------
# SKU and Network Configuration
#------------------------------------------------------------------------------

# sku - The pricing tier for ACR
# Basic: For dev/test, no premium features
# Standard: For production with standard features
# Premium: For production with geo-replication, private endpoints, retention policies
variable "sku" {
  description = "SKU tier for ACR (Basic, Standard, or Premium)"
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "SKU must be Basic, Standard, or Premium"
  }
}

# public_network_access_enabled - Whether to allow public internet access
# true: Allow public access (suitable for dev)
# false: Require private endpoints (recommended for production)
variable "public_network_access_enabled" {
  description = "Whether to enable public network access to ACR (set to false for production with private endpoints)"
  type        = bool
  default     = true
}

#------------------------------------------------------------------------------
# Security Configuration
#------------------------------------------------------------------------------

# encryption_enabled - Customer-managed encryption keys
# Requires Premium SKU and Key Vault integration
variable "encryption_enabled" {
  description = "Enable encryption with customer-managed keys (Premium SKU only)"
  type        = bool
  default     = false
}

# trust_policy_enabled - Enable Docker Content Trust
# Allows signing and verification of container images
variable "trust_policy_enabled" {
  description = "Enable content trust policy for image signing (Premium SKU only)"
  type        = bool
  default     = false
}

# create_scope_maps - Create scope maps for token-based auth
# Used for granular access control to repositories
variable "create_scope_maps" {
  description = "Create scope maps for token-based authentication"
  type        = bool
  default     = false
}

#------------------------------------------------------------------------------
# Retention Configuration
#------------------------------------------------------------------------------

# retention_enabled - Automatically clean up untagged images
# Helps manage storage costs by removing old untagged manifests
variable "retention_enabled" {
  description = "Enable retention policy for untagged manifests (Premium SKU only)"
  type        = bool
  default     = false
}

# retention_days - How long to keep untagged manifests
# Only applies when retention_enabled is true
variable "retention_days" {
  description = "Number of days to retain untagged manifests before automatic deletion"
  type        = number
  default     = 7

  validation {
    condition     = var.retention_days >= 0 && var.retention_days <= 365
    error_message = "Retention days must be between 0 and 365"
  }
}

#------------------------------------------------------------------------------
# Diagnostic Settings
#------------------------------------------------------------------------------

# enable_diagnostics - Enable diagnostic logging to Log Analytics
# Recommended for production to monitor access and troubleshoot issues
variable "enable_diagnostics" {
  description = "Enable diagnostic settings for the container registry"
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
# Optional Variables
#------------------------------------------------------------------------------

# tags - Resource tags for organization and cost management
variable "tags" {
  description = "Tags to apply to the container registry"
  type        = map(string)
  default     = {}
}
