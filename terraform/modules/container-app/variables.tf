#------------------------------------------------------------------------------
# Azure Container App Module - variables.tf
#------------------------------------------------------------------------------
# Input variable definitions for the Azure Container App module.
# Container Apps provides serverless container hosting with automatic scaling,
# managed identity, and built-in ingress capabilities.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Required Variables - Identity
#------------------------------------------------------------------------------

# name - Name of the container app
# Must be lowercase alphanumeric with hyphens, max 32 characters
variable "name" {
  description = "Name of the container app"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,31}$", var.name))
    error_message = "Container app name must be lowercase alphanumeric with hyphens, max 32 chars"
  }
}

# environment_name - Name of the container app environment
# Shared hosting context for related container apps
variable "environment_name" {
  description = "Name of the container app environment"
  type        = string
}

# resource_group_name - The resource group for the container app
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

# location - Azure region for the container app
variable "location" {
  description = "Azure region"
  type        = string
}

# tags - Resource tags for organization and cost management
variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

#------------------------------------------------------------------------------
# Environment Configuration
#------------------------------------------------------------------------------

# log_analytics_workspace_id - Workspace for container logs
# Required for log output and console streaming
variable "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace for container logs"
  type        = string
}

# infrastructure_subnet_id - Subnet for VNet integration
# null = Azure-managed network (simpler)
# Subnet ID = Custom VNet (more control, required for private endpoints)
variable "infrastructure_subnet_id" {
  description = "Subnet ID for VNet integration (null for Azure-managed network)"
  type        = string
  default     = null
}

# internal_load_balancer_enabled - Use private IP for ingress
# Only applicable when infrastructure_subnet_id is set
variable "internal_load_balancer_enabled" {
  description = "Enable internal load balancer (private ingress)"
  type        = bool
  default     = false
}

# zone_redundancy_enabled - Deploy across availability zones
# Only applicable when infrastructure_subnet_id is set
# Recommended for production workloads
variable "zone_redundancy_enabled" {
  description = "Enable zone redundancy for high availability"
  type        = bool
  default     = false
}

#------------------------------------------------------------------------------
# Container App Configuration
#------------------------------------------------------------------------------

# revision_mode - How revisions are managed
# Single: One active revision (simpler)
# Multiple: Multiple revisions (blue/green deployments)
variable "revision_mode" {
  description = "Revision mode (Single or Multiple)"
  type        = string
  default     = "Single"

  validation {
    condition     = contains(["Single", "Multiple"], var.revision_mode)
    error_message = "Revision mode must be Single or Multiple"
  }
}

# revision_suffix - Custom suffix for revision names
# null = Azure generates unique suffix
variable "revision_suffix" {
  description = "Suffix for revision naming (optional)"
  type        = string
  default     = null
}

#------------------------------------------------------------------------------
# Container Configuration
#------------------------------------------------------------------------------

# container_name - Name of the container
variable "container_name" {
  description = "Name of the container"
  type        = string
  default     = "api"
}

# container_image - Full container image path
# Format: registry/image:tag
# Example: myregistry.azurecr.io/myapp:v1.0.0
variable "container_image" {
  description = "Full container image path (registry/image:tag)"
  type        = string
}

# container_cpu - CPU allocation (0.25 - 2.0 vCPU)
variable "container_cpu" {
  description = "CPU allocation (0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0)"
  type        = number
  default     = 0.5

  validation {
    condition     = contains([0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], var.container_cpu)
    error_message = "CPU must be 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, or 2.0"
  }
}

# container_memory - Memory allocation (0.5Gi - 4Gi)
variable "container_memory" {
  description = "Memory allocation (0.5Gi, 1Gi, 1.5Gi, 2Gi, 3Gi, 4Gi)"
  type        = string
  default     = "1Gi"

  validation {
    condition     = contains(["0.5Gi", "1Gi", "1.5Gi", "2Gi", "3Gi", "4Gi"], var.container_memory)
    error_message = "Memory must be 0.5Gi, 1Gi, 1.5Gi, 2Gi, 3Gi, or 4Gi"
  }
}

#------------------------------------------------------------------------------
# Environment Variables and Secrets
#------------------------------------------------------------------------------

# environment_variables - Non-sensitive environment variables
# Visible in Azure Portal and logs
variable "environment_variables" {
  description = "Map of environment variables (non-sensitive)"
  type        = map(string)
  default     = {}
}

# secret_environment_variables - Secret environment variable references
# References secrets stored in the Container App
variable "secret_environment_variables" {
  description = "Map of secret environment variables (references to secrets)"
  type        = map(string)
  default     = {}
}

# secrets - Secrets to store in Container App
# Note: Not marked sensitive to allow for_each
# Prefer Key Vault SDK in application for sensitive secrets
variable "secrets" {
  description = "Map of secrets to store in Container App. Note: Not marked sensitive to allow for_each, but values are still protected in state."
  type        = map(string)
  default     = {}
  # NOTE: sensitive = true cannot be used with for_each in Terraform
}

#------------------------------------------------------------------------------
# Scaling Configuration
#------------------------------------------------------------------------------

# min_replicas - Minimum number of replicas
# 0 = scale to zero (cost savings, cold starts)
# 1+ = always running (no cold starts)
variable "min_replicas" {
  description = "Minimum number of replicas (0 for scale to zero)"
  type        = number
  default     = 1

  validation {
    condition     = var.min_replicas >= 0 && var.min_replicas <= 30
    error_message = "Min replicas must be between 0 and 30"
  }
}

# max_replicas - Maximum number of replicas
variable "max_replicas" {
  description = "Maximum number of replicas"
  type        = number
  default     = 10

  validation {
    condition     = var.max_replicas >= 1 && var.max_replicas <= 30
    error_message = "Max replicas must be between 1 and 30"
  }
}

# http_scale_rule_enabled - Enable HTTP-based autoscaling
variable "http_scale_rule_enabled" {
  description = "Enable HTTP-based scaling"
  type        = bool
  default     = true
}

# http_scale_concurrent_requests - Requests per replica before scaling
variable "http_scale_concurrent_requests" {
  description = "Concurrent requests per replica before scaling"
  type        = number
  default     = 100
}

# custom_scale_rules - Custom KEDA scale rules
# For queue-based, CPU/memory, or custom metric scaling
variable "custom_scale_rules" {
  description = "List of custom scale rules (for queue-based, etc.)"
  type = list(object({
    name     = string
    type     = string
    metadata = map(string)
  }))
  default = []
}

#------------------------------------------------------------------------------
# Health Probes - Startup
#------------------------------------------------------------------------------

variable "startup_probe_enabled" {
  description = "Enable startup probe"
  type        = bool
  default     = false
}

variable "startup_probe_transport" {
  description = "Startup probe transport (HTTP or TCP)"
  type        = string
  default     = "HTTP"
}

variable "startup_probe_port" {
  description = "Startup probe port"
  type        = number
  default     = 8080
}

variable "startup_probe_path" {
  description = "Startup probe HTTP path"
  type        = string
  default     = "/health"
}

variable "startup_probe_initial_delay" {
  description = "Startup probe initial delay in seconds"
  type        = number
  default     = 5
}

variable "startup_probe_interval" {
  description = "Startup probe interval in seconds"
  type        = number
  default     = 10
}

variable "startup_probe_timeout" {
  description = "Startup probe timeout in seconds"
  type        = number
  default     = 3
}

variable "startup_probe_failure_threshold" {
  description = "Startup probe failure threshold"
  type        = number
  default     = 3
}

#------------------------------------------------------------------------------
# Health Probes - Liveness
#------------------------------------------------------------------------------

variable "liveness_probe_enabled" {
  description = "Enable liveness probe"
  type        = bool
  default     = true
}

variable "liveness_probe_transport" {
  description = "Liveness probe transport (HTTP or TCP)"
  type        = string
  default     = "HTTP"
}

variable "liveness_probe_port" {
  description = "Liveness probe port"
  type        = number
  default     = 8080
}

variable "liveness_probe_path" {
  description = "Liveness probe HTTP path"
  type        = string
  default     = "/health"
}

variable "liveness_probe_initial_delay" {
  description = "Liveness probe initial delay in seconds"
  type        = number
  default     = 10
}

variable "liveness_probe_interval" {
  description = "Liveness probe interval in seconds"
  type        = number
  default     = 30
}

variable "liveness_probe_timeout" {
  description = "Liveness probe timeout in seconds"
  type        = number
  default     = 3
}

variable "liveness_probe_failure_threshold" {
  description = "Liveness probe failure threshold"
  type        = number
  default     = 3
}

#------------------------------------------------------------------------------
# Health Probes - Readiness
#------------------------------------------------------------------------------

variable "readiness_probe_enabled" {
  description = "Enable readiness probe"
  type        = bool
  default     = true
}

variable "readiness_probe_transport" {
  description = "Readiness probe transport (HTTP or TCP)"
  type        = string
  default     = "HTTP"
}

variable "readiness_probe_port" {
  description = "Readiness probe port"
  type        = number
  default     = 8080
}

variable "readiness_probe_path" {
  description = "Readiness probe HTTP path"
  type        = string
  default     = "/ready"
}

variable "readiness_probe_interval" {
  description = "Readiness probe interval in seconds"
  type        = number
  default     = 10
}

variable "readiness_probe_timeout" {
  description = "Readiness probe timeout in seconds"
  type        = number
  default     = 3
}

variable "readiness_probe_failure_threshold" {
  description = "Readiness probe failure threshold"
  type        = number
  default     = 3
}

variable "readiness_probe_success_threshold" {
  description = "Readiness probe success threshold"
  type        = number
  default     = 1
}

#------------------------------------------------------------------------------
# Ingress Configuration
#------------------------------------------------------------------------------

variable "ingress_enabled" {
  description = "Enable ingress (HTTP/HTTPS traffic)"
  type        = bool
  default     = true
}

variable "ingress_external_enabled" {
  description = "Enable external ingress (public internet)"
  type        = bool
  default     = true
}

variable "ingress_target_port" {
  description = "Target port for ingress traffic"
  type        = number
  default     = 8080
}

variable "ingress_transport" {
  description = "Ingress transport protocol (http, http2, tcp)"
  type        = string
  default     = "http"

  validation {
    condition     = contains(["http", "http2", "tcp"], var.ingress_transport)
    error_message = "Transport must be http, http2, or tcp"
  }
}

variable "allow_insecure_connections" {
  description = "Allow insecure HTTP connections (false = HTTPS only)"
  type        = bool
  default     = false
}

variable "traffic_latest_revision" {
  description = "Route traffic to latest revision"
  type        = bool
  default     = true
}

variable "traffic_percentage" {
  description = "Percentage of traffic to route"
  type        = number
  default     = 100

  validation {
    condition     = var.traffic_percentage >= 0 && var.traffic_percentage <= 100
    error_message = "Traffic percentage must be between 0 and 100"
  }
}

variable "traffic_label" {
  description = "Label for traffic split (optional)"
  type        = string
  default     = null
}

variable "ip_security_restrictions" {
  description = "List of IP security restrictions"
  type = list(object({
    name             = string
    ip_address_range = string
    action           = string
    description      = string
  }))
  default = []
}

#------------------------------------------------------------------------------
# CORS Configuration (Note: Handled at application level)
#------------------------------------------------------------------------------

variable "cors_enabled" {
  description = "Enable CORS configuration"
  type        = bool
  default     = false
}

variable "cors_allowed_origins" {
  description = "List of allowed CORS origins"
  type        = list(string)
  default     = ["*"]
}

variable "cors_allowed_methods" {
  description = "List of allowed CORS methods"
  type        = list(string)
  default     = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
}

variable "cors_allowed_headers" {
  description = "List of allowed CORS headers"
  type        = list(string)
  default     = ["*"]
}

variable "cors_expose_headers" {
  description = "List of exposed CORS headers"
  type        = list(string)
  default     = []
}

variable "cors_max_age" {
  description = "CORS max age in seconds"
  type        = number
  default     = 3600
}

variable "cors_allow_credentials" {
  description = "Allow CORS credentials"
  type        = bool
  default     = false
}

#------------------------------------------------------------------------------
# Registry Configuration
#------------------------------------------------------------------------------

variable "registry_server" {
  description = "Container registry server (e.g., myregistry.azurecr.io)"
  type        = string
  default     = ""
}

variable "enable_acr_pull" {
  description = "Enable ACR pull role assignment for the container app"
  type        = bool
  default     = false
}

variable "container_registry_id" {
  description = "ID of the container registry for RBAC assignment (required if enable_acr_pull = true)"
  type        = string
  default     = ""
}

#------------------------------------------------------------------------------
# Key Vault Access Configuration
#------------------------------------------------------------------------------

variable "enable_key_vault_access" {
  description = "Enable Key Vault secrets user role assignment for the container app"
  type        = bool
  default     = false
}

variable "key_vault_id" {
  description = "ID of the Key Vault for RBAC assignment (required if enable_key_vault_access = true)"
  type        = string
  default     = ""
}

#------------------------------------------------------------------------------
# Dapr Configuration (Optional - for microservices)
#------------------------------------------------------------------------------

variable "dapr_enabled" {
  description = "Enable Dapr sidecar"
  type        = bool
  default     = false
}

variable "dapr_app_id" {
  description = "Dapr application ID"
  type        = string
  default     = null
}

variable "dapr_app_protocol" {
  description = "Dapr application protocol (http, grpc)"
  type        = string
  default     = "http"
}

variable "dapr_app_port" {
  description = "Dapr application port"
  type        = number
  default     = null
}
