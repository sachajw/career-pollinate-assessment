#------------------------------------------------------------------------------
# Azure Observability Module - variables.tf
#------------------------------------------------------------------------------
# Input variable definitions for the observability module.
# This module creates Log Analytics and Application Insights for comprehensive
# application monitoring and centralized log management.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Common Variables
#------------------------------------------------------------------------------

# resource_group_name - The resource group for all observability resources
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

# location - Azure region for the observability resources
variable "location" {
  description = "Azure region for resources"
  type        = string
}

# tags - Resource tags for organization and cost management
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

#------------------------------------------------------------------------------
# Log Analytics Configuration
#------------------------------------------------------------------------------

# log_analytics_name - Name of the Log Analytics workspace
# Must be 4-63 characters, alphanumeric and hyphens only
variable "log_analytics_name" {
  description = "Name of the Log Analytics workspace"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{4,63}$", var.log_analytics_name))
    error_message = "Log Analytics name must be 4-63 characters, alphanumeric and hyphens only"
  }
}

# log_analytics_sku - Pricing tier for Log Analytics
# PerGB2018: Pay per GB ingested (standard)
# Free: Limited features, 7-day retention
variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"

  validation {
    condition     = contains(["PerGB2018", "Free"], var.log_analytics_sku)
    error_message = "SKU must be PerGB2018 or Free"
  }
}

# log_analytics_retention_days - How long to retain log data
# 7-730 days (30 days for Free tier)
variable "log_analytics_retention_days" {
  description = "Data retention in days for Log Analytics (30-730, or 7 for Free tier)"
  type        = number
  default     = 30

  validation {
    condition     = (var.log_analytics_retention_days >= 7 && var.log_analytics_retention_days <= 730)
    error_message = "Retention must be between 7 and 730 days"
  }
}

# log_analytics_daily_quota_gb - Daily ingestion cap
# Prevents unexpected cost spikes. null = unlimited.
variable "log_analytics_daily_quota_gb" {
  description = "Daily ingestion quota in GB (null for unlimited)"
  type        = number
  default     = null
}

#------------------------------------------------------------------------------
# Application Insights Configuration
#------------------------------------------------------------------------------

# app_insights_name - Name of the Application Insights instance
variable "app_insights_name" {
  description = "Name of the Application Insights instance"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_\\.]{1,255}$", var.app_insights_name))
    error_message = "Application Insights name must be 1-255 characters"
  }
}

# application_type - Type of application being monitored
# Affects default telemetry collection behavior
variable "application_type" {
  description = "Application type for App Insights (web, other, java, Node.JS, etc.)"
  type        = string
  default     = "web"

  validation {
    condition     = contains(["web", "other", "java", "Node.JS"], var.application_type)
    error_message = "Application type must be web, other, java, or Node.JS"
  }
}

# sampling_percentage - Percentage of telemetry to retain
# 100 = capture all, lower values reduce cost but may miss issues
variable "sampling_percentage" {
  description = "Percentage of telemetry to sample (1-100)"
  type        = number
  default     = 100

  validation {
    condition     = var.sampling_percentage >= 1 && var.sampling_percentage <= 100
    error_message = "Sampling percentage must be between 1 and 100"
  }
}

# app_insights_retention_days - Retention override for App Insights
# null = use Log Analytics workspace retention
variable "app_insights_retention_days" {
  description = "Data retention in days for App Insights (null to use workspace default)"
  type        = number
  default     = null
}

# app_insights_daily_cap_gb - Daily data cap
# Prevents runaway telemetry costs. null = unlimited.
variable "app_insights_daily_cap_gb" {
  description = "Daily data cap in GB for App Insights (null for unlimited)"
  type        = number
  default     = null
}

#------------------------------------------------------------------------------
# Security and Network Configuration
#------------------------------------------------------------------------------

# disable_ip_masking - Whether to show full IP addresses
# true: Show full IPs (easier debugging in dev)
# false: Mask last octet (privacy in production)
variable "disable_ip_masking" {
  description = "Disable IP address masking for better debugging (false for production)"
  type        = bool
  default     = true
}

# local_authentication_disabled - Whether to disable API key auth
# true: Require AAD/RBAC (recommended for production)
# false: Allow API key auth (easier for dev)
variable "local_authentication_disabled" {
  description = "Disable local authentication (use AAD/RBAC instead)"
  type        = bool
  default     = false
}

# internet_ingestion_enabled - Allow telemetry ingestion from internet
# true: Allow public internet (dev)
# false: Require private link (production)
variable "internet_ingestion_enabled" {
  description = "Enable internet ingestion for telemetry"
  type        = bool
  default     = true
}

# internet_query_enabled - Allow queries from internet
# true: Allow public internet (dev)
# false: Require private link (production)
variable "internet_query_enabled" {
  description = "Enable internet query access"
  type        = bool
  default     = true
}

#------------------------------------------------------------------------------
# Availability Test Configuration
#------------------------------------------------------------------------------

# create_availability_test - Whether to create synthetic monitoring
variable "create_availability_test" {
  description = "Create an availability test for health check endpoint"
  type        = bool
  default     = false
}

# health_check_url - URL to test for availability
# Required if create_availability_test is true
variable "health_check_url" {
  description = "URL for health check endpoint (required if create_availability_test = true)"
  type        = string
  default     = null
}

# test_locations - Azure regions to run availability tests from
# Multiple locations provide redundancy and global perspective
variable "test_locations" {
  description = "List of Azure regions to run availability tests from"
  type        = list(string)
  default = [
    "us-va-ash-azr", # US East (Ashburn, VA)
    "us-ca-sjc-azr", # US West (San Jose, CA)
  ]
}

# health_check_headers - HTTP headers for health check requests
# Useful for authentication or custom headers
variable "health_check_headers" {
  description = "HTTP headers for health check request"
  type        = map(string)
  default     = {}
}
