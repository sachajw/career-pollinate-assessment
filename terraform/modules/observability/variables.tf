# Observability Module Variables

# Common Variables
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Log Analytics Variables
variable "log_analytics_name" {
  description = "Name of the Log Analytics workspace"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{4,63}$", var.log_analytics_name))
    error_message = "Log Analytics name must be 4-63 characters, alphanumeric and hyphens only"
  }
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"

  validation {
    condition     = contains(["PerGB2018", "Free"], var.log_analytics_sku)
    error_message = "SKU must be PerGB2018 or Free"
  }
}

variable "log_analytics_retention_days" {
  description = "Data retention in days for Log Analytics (30-730, or 7 for Free tier)"
  type        = number
  default     = 30

  validation {
    condition     = (var.log_analytics_retention_days >= 7 && var.log_analytics_retention_days <= 730)
    error_message = "Retention must be between 7 and 730 days"
  }
}

variable "log_analytics_daily_quota_gb" {
  description = "Daily ingestion quota in GB (null for unlimited)"
  type        = number
  default     = null
}

# Application Insights Variables
variable "app_insights_name" {
  description = "Name of the Application Insights instance"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_\\.]{1,255}$", var.app_insights_name))
    error_message = "Application Insights name must be 1-255 characters"
  }
}

variable "application_type" {
  description = "Application type for App Insights (web, other, java, Node.JS, etc.)"
  type        = string
  default     = "web"

  validation {
    condition     = contains(["web", "other", "java", "Node.JS"], var.application_type)
    error_message = "Application type must be web, other, java, or Node.JS"
  }
}

variable "sampling_percentage" {
  description = "Percentage of telemetry to sample (1-100)"
  type        = number
  default     = 100

  validation {
    condition     = var.sampling_percentage >= 1 && var.sampling_percentage <= 100
    error_message = "Sampling percentage must be between 1 and 100"
  }
}

variable "app_insights_retention_days" {
  description = "Data retention in days for App Insights (null to use workspace default)"
  type        = number
  default     = null
}

variable "app_insights_daily_cap_gb" {
  description = "Daily data cap in GB for App Insights (null for unlimited)"
  type        = number
  default     = null
}

variable "disable_ip_masking" {
  description = "Disable IP address masking for better debugging (false for production)"
  type        = bool
  default     = true # true for dev, false for prod
}

variable "local_authentication_disabled" {
  description = "Disable local authentication (use AAD/RBAC instead)"
  type        = bool
  default     = false
}

variable "internet_ingestion_enabled" {
  description = "Enable internet ingestion for telemetry"
  type        = bool
  default     = true # false for prod with private link
}

variable "internet_query_enabled" {
  description = "Enable internet query access"
  type        = bool
  default     = true # false for prod with private link
}

# Availability Test Variables
variable "create_availability_test" {
  description = "Create an availability test for health check endpoint"
  type        = bool
  default     = false
}

variable "health_check_url" {
  description = "URL for health check endpoint (required if create_availability_test = true)"
  type        = string
  default     = null
}

variable "test_locations" {
  description = "List of Azure regions to run availability tests from"
  type        = list(string)
  default = [
    "us-va-ash-azr", # US East
    "us-ca-sjc-azr", # US West
  ]
}

variable "health_check_headers" {
  description = "HTTP headers for health check request"
  type        = map(string)
  default     = {}
}
