# Azure Container App Module
# This module creates an Azure Container App and its environment
# Features:
# - System-assigned managed identity
# - Auto-scaling configuration
# - Ingress with HTTPS
# - Integration with Log Analytics
# - Environment variables and secrets
# - Health probes

# Container App Environment
# Shared environment for one or more container apps
resource "azurerm_container_app_environment" "this" {
  name                = var.environment_name
  resource_group_name = var.resource_group_name
  location            = var.location

  # Link to Log Analytics for logging
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # Infrastructure subnet (for VNet integration in production)
  # null for dev (uses Azure-managed network)
  infrastructure_subnet_id = var.infrastructure_subnet_id

  # Internal load balancer (for private ingress)
  # false for dev (public ingress), true for prod
  internal_load_balancer_enabled = var.internal_load_balancer_enabled

  # Zone redundancy (for high availability in production)
  # false for dev, true for prod (requires 3+ zones)
  zone_redundancy_enabled = var.zone_redundancy_enabled

  tags = var.tags
}

# Container App
# The actual application deployment
resource "azurerm_container_app" "this" {
  name                         = var.name
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.this.id
  revision_mode                = var.revision_mode

  # System-assigned managed identity for Azure service authentication
  # This identity will be granted access to Key Vault, ACR, etc.
  identity {
    type = "SystemAssigned"
  }

  # Template defines the container configuration
  template {
    # Scaling configuration
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    # Revision suffix for naming (optional)
    revision_suffix = var.revision_suffix

    # Container definition
    container {
      name   = var.container_name
      image  = var.container_image
      cpu    = var.container_cpu
      memory = var.container_memory

      # Environment variables (non-sensitive)
      dynamic "env" {
        for_each = var.environment_variables
        content {
          name  = env.key
          value = env.value
        }
      }

      # Secrets (loaded from Key Vault at runtime)
      # Note: These are references to secrets stored in Container App environment
      # Not the actual secret values
      dynamic "env" {
        for_each = var.secret_environment_variables
        content {
          name        = env.key
          secret_name = env.value
        }
      }

      # Startup probe (ensures container started successfully)
      dynamic "startup_probe" {
        for_each = var.startup_probe_enabled ? [1] : []
        content {
          transport = var.startup_probe_transport
          port      = var.startup_probe_port
          path      = var.startup_probe_path

          initial_delay = var.startup_probe_initial_delay
          interval      = var.startup_probe_interval
          timeout       = var.startup_probe_timeout
          failure_count_threshold = var.startup_probe_failure_threshold
        }
      }

      # Liveness probe (checks if container is healthy)
      dynamic "liveness_probe" {
        for_each = var.liveness_probe_enabled ? [1] : []
        content {
          transport = var.liveness_probe_transport
          port      = var.liveness_probe_port
          path      = var.liveness_probe_path

          initial_delay = var.liveness_probe_initial_delay
          interval      = var.liveness_probe_interval
          timeout       = var.liveness_probe_timeout
          failure_count_threshold = var.liveness_probe_failure_threshold
        }
      }

      # Readiness probe (checks if container can accept traffic)
      dynamic "readiness_probe" {
        for_each = var.readiness_probe_enabled ? [1] : []
        content {
          transport = var.readiness_probe_transport
          port      = var.readiness_probe_port
          path      = var.readiness_probe_path

          interval      = var.readiness_probe_interval
          timeout       = var.readiness_probe_timeout
          failure_count_threshold = var.readiness_probe_failure_threshold
          success_count_threshold = var.readiness_probe_success_threshold
        }
      }
    }

    # HTTP scale rule (autoscaling based on concurrent requests)
    dynamic "http_scale_rule" {
      for_each = var.http_scale_rule_enabled ? [1] : []
      content {
        name                = "http-scaling"
        concurrent_requests = var.http_scale_concurrent_requests
      }
    }

    # Custom scale rules (for advanced scenarios like queue-based scaling)
    dynamic "custom_scale_rule" {
      for_each = var.custom_scale_rules
      content {
        name             = custom_scale_rule.value.name
        custom_rule_type = custom_scale_rule.value.type
        metadata         = custom_scale_rule.value.metadata
      }
    }
  }

  # Ingress configuration (HTTP/HTTPS traffic)
  dynamic "ingress" {
    for_each = var.ingress_enabled ? [1] : []
    content {
      # External ingress (public internet access)
      # Set to false for internal-only apps
      external_enabled = var.ingress_external_enabled

      # Target port (where container listens)
      target_port = var.ingress_target_port

      # Transport protocol (http, http2, tcp)
      transport = var.ingress_transport

      # Allow insecure connections (false = HTTPS only)
      allow_insecure_connections = var.allow_insecure_connections

      # Traffic weight (for blue/green deployments)
      traffic_weight {
        latest_revision = var.traffic_latest_revision
        percentage      = var.traffic_percentage
        label           = var.traffic_label
      }

      # IP security restrictions (whitelist/blacklist)
      dynamic "ip_security_restriction" {
        for_each = var.ip_security_restrictions
        content {
          name             = ip_security_restriction.value.name
          ip_address_range = ip_security_restriction.value.ip_address_range
          action           = ip_security_restriction.value.action
          description      = ip_security_restriction.value.description
        }
      }

      # CORS configuration (for web applications)
      dynamic "cors" {
        for_each = var.cors_enabled ? [1] : []
        content {
          allowed_origins     = var.cors_allowed_origins
          allowed_methods     = var.cors_allowed_methods
          allowed_headers     = var.cors_allowed_headers
          expose_headers      = var.cors_expose_headers
          max_age_in_seconds  = var.cors_max_age
          allow_credentials   = var.cors_allow_credentials
        }
      }
    }
  }

  # Registry credentials (for pulling from private ACR)
  # This is automatically handled by managed identity for ACR
  # but can be explicitly configured if needed
  dynamic "registry" {
    for_each = var.registry_server != null ? [1] : []
    content {
      server   = var.registry_server
      identity = azurerm_container_app.this.identity[0].principal_id
    }
  }

  # Secrets (stored in Container App, referenced in env vars)
  # These should be minimal - prefer Key Vault SDK in application
  dynamic "secret" {
    for_each = var.secrets
    content {
      name  = secret.key
      value = secret.value
    }
  }

  # Dapr configuration (for microservices, out of scope for dev)
  dynamic "dapr" {
    for_each = var.dapr_enabled ? [1] : []
    content {
      app_id       = var.dapr_app_id
      app_protocol = var.dapr_app_protocol
      app_port     = var.dapr_app_port
    }
  }

  tags = var.tags
}

# RBAC: Grant Container App managed identity access to ACR
# This allows the container app to pull images without credentials
resource "azurerm_role_assignment" "acr_pull" {
  count = var.container_registry_id != null ? 1 : 0

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_container_app.this.identity[0].principal_id
}

# RBAC: Grant Container App managed identity access to Key Vault
# This allows the application to read secrets at runtime
resource "azurerm_role_assignment" "keyvault_secrets_user" {
  count = var.key_vault_id != null ? 1 : 0

  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_container_app.this.identity[0].principal_id
}
