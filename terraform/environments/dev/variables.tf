# Development Environment Variables
# These variables can be overridden via terraform.tfvars or command line

variable "subscription_id" {
  description = "Azure subscription ID (override via environment variable)"
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus2"
}

variable "project_name" {
  description = "Project name for resource naming (FinSure Risk Validation context)"
  type        = string
  default     = "finrisk"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod"
  }
}

variable "enable_availability_test" {
  description = "Enable Application Insights availability test"
  type        = bool
  default     = false
}

variable "container_app_min_replicas" {
  description = "Minimum replicas for container app (0 = scale to zero)"
  type        = number
  default     = 0

  validation {
    condition     = var.container_app_min_replicas >= 0 && var.container_app_min_replicas <= 10
    error_message = "Min replicas must be between 0 and 10"
  }
}

variable "container_app_max_replicas" {
  description = "Maximum replicas for container app"
  type        = number
  default     = 5

  validation {
    condition     = var.container_app_max_replicas >= 1 && var.container_app_max_replicas <= 30
    error_message = "Max replicas must be between 1 and 30"
  }
}

variable "log_analytics_retention_days" {
  description = "Log retention in days"
  type        = number
  default     = 30

  validation {
    condition     = var.log_analytics_retention_days >= 7 && var.log_analytics_retention_days <= 730
    error_message = "Retention must be between 7 and 730 days"
  }
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

#------------------------------------------------------------------------------
# Custom Domain and Certificate Configuration
#------------------------------------------------------------------------------

variable "custom_domain_enabled" {
  description = "Enable custom domain with certificate"
  type        = bool
  default     = false
}

variable "custom_domain_name" {
  description = "Custom domain name (e.g., finrisk.pangarabbit.com)"
  type        = string
  default     = ""
}

variable "certificate_name" {
  description = "Name of existing certificate in Container App Environment (uploaded via Azure CLI)"
  type        = string
  default     = "finrisk-pangarabbit-cert"
}
