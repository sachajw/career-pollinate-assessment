#------------------------------------------------------------------------------
# Azure Container App Module - main.tf
#------------------------------------------------------------------------------
# This module creates an Azure Container App and its hosting environment.
# Container Apps provides serverless container hosting with:
# - Automatic scaling (including scale-to-zero)
# - Built-in ingress with HTTPS
# - Managed Identity for secure Azure service access
# - Health probes for reliability
# - Revision management for deployments
#
# Usage:
#   module "container_app" {
#     source = "../../modules/container-app"
#     name                      = "ca-myapp-dev"
#     environment_name          = "cae-myapp-dev"
#     resource_group_name       = "rg-myapp-dev"
#     location                  = "eastus2"
#     log_analytics_workspace_id = module.observability.log_analytics_workspace_id
#     container_image           = "myregistry.azurecr.io/myapp:latest"
#     tags                      = { Environment = "dev" }
#   }
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Container App Environment
#------------------------------------------------------------------------------
# The environment is a shared hosting context for one or more container apps.
# All apps in the same environment share:
# - Network configuration
# - Log Analytics workspace
# - Dapr configuration (if enabled)
#
# The environment can be:
# - External: Azure-managed network (simpler, suitable for dev)
# - Internal: Custom VNet (more control, required for private endpoints)
#------------------------------------------------------------------------------
resource "azurerm_container_app_environment" "this" {
  name                = var.environment_name
  resource_group_name = var.resource_group_name
  location            = var.location

  # Log Analytics workspace for container logs and console output
  # All apps in this environment send logs here
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # VNet integration (optional)
  # When specified: Uses custom VNet for network isolation
  # When null: Uses Azure-managed network (simpler setup)
  #
  # IMPORTANT: The following attributes are only valid when infrastructure_subnet_id is set:
  # - internal_load_balancer_enabled: Use private IP for ingress
  # - zone_redundancy_enabled: Deploy across availability zones
  infrastructure_subnet_id       = var.infrastructure_subnet_id
  internal_load_balancer_enabled = var.infrastructure_subnet_id != null ? var.internal_load_balancer_enabled : null
  zone_redundancy_enabled        = var.infrastructure_subnet_id != null ? var.zone_redundancy_enabled : null

  # Resource tags for organization and cost management
  tags = var.tags
}

#------------------------------------------------------------------------------
# Container App
#------------------------------------------------------------------------------
# The container app runs your containerized application with:
# - Automatic scaling based on HTTP requests or custom metrics
# - Managed Identity for passwordless Azure service access
# - Health probes for reliability
# - Ingress configuration for HTTP/HTTPS traffic
#------------------------------------------------------------------------------
resource "azurerm_container_app" "this" {
  name                         = var.name
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.this.id

  # Revision mode:
  # - Single: Only one revision active at a time (simpler)
  # - Multiple: Multiple revisions for blue/green deployments
  revision_mode = var.revision_mode

  # System-assigned managed identity
  # This identity is used to authenticate with Azure services:
  # - Azure Container Registry (pull images)
  # - Azure Key Vault (read secrets)
  # - Azure Storage, SQL, etc.
  identity {
    type = "SystemAssigned"
  }

  # Container template configuration
  template {
    # Scaling configuration
    # min_replicas = 0 enables scale-to-zero (cost savings for dev)
    # Increase min_replicas for production workloads
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    # Optional revision suffix for custom naming
    # If null, Azure generates a unique suffix
    revision_suffix = var.revision_suffix

    # Container definition
    container {
      # Container name (identifier within the app)
      name = var.container_name

      # Full image path: registry/image:tag
      # Example: myregistry.azurecr.io/myapp:v1.0.0
      image = var.container_image

      # CPU allocation (0.25 - 2.0 vCPU)
      # Must be paired with appropriate memory
      cpu = var.container_cpu

      # Memory allocation (0.5Gi - 4Gi)
      # Rule: 0.5Gi per 0.25 vCPU, 1Gi per 0.5 vCPU, etc.
      memory = var.container_memory

      # Environment variables (non-sensitive)
      # These are visible in the Azure Portal and logs
      dynamic "env" {
        for_each = var.environment_variables
        content {
          name  = env.key
          value = env.value
        }
      }

      # Secret environment variables
      # References secrets stored in the Container App
      # Values come from Key Vault at runtime (recommended)
      dynamic "env" {
        for_each = var.secret_environment_variables
        content {
          name        = env.key
          secret_name = env.value
        }
      }

      # Startup probe (optional)
      # Checks if the container has started successfully
      # If failed, container is restarted
      # Useful for slow-starting applications
      dynamic "startup_probe" {
        for_each = var.startup_probe_enabled ? [1] : []
        content {
          transport               = var.startup_probe_transport
          port                    = var.startup_probe_port
          path                    = var.startup_probe_path
          failure_count_threshold = var.startup_probe_failure_threshold
        }
      }

      # Liveness probe (optional but recommended)
      # Checks if the container is healthy and running
      # If failed, container is restarted
      dynamic "liveness_probe" {
        for_each = var.liveness_probe_enabled ? [1] : []
        content {
          transport               = var.liveness_probe_transport
          port                    = var.liveness_probe_port
          path                    = var.liveness_probe_path
          failure_count_threshold = var.liveness_probe_failure_threshold
        }
      }

      # Readiness probe (optional but recommended)
      # Checks if the container is ready to accept traffic
      # If failed, removed from load balancer (not restarted)
      dynamic "readiness_probe" {
        for_each = var.readiness_probe_enabled ? [1] : []
        content {
          transport               = var.readiness_probe_transport
          port                    = var.readiness_probe_port
          path                    = var.readiness_probe_path
          failure_count_threshold = var.readiness_probe_failure_threshold
          success_count_threshold = var.readiness_probe_success_threshold
        }
      }
    }

    # HTTP-based autoscaling (KEDA)
    # Scales based on concurrent HTTP requests
    dynamic "http_scale_rule" {
      for_each = var.http_scale_rule_enabled ? [1] : []
      content {
        name                = "http-scaling"
        concurrent_requests = var.http_scale_concurrent_requests
      }
    }

    # Custom scale rules (advanced scenarios)
    # Examples: Queue-based scaling, CPU/memory-based, etc.
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
  # When enabled, provides:
  # - Load balancing
  # - HTTPS termination
  # - Custom domain support
  # - Traffic splitting for deployments
  dynamic "ingress" {
    for_each = var.ingress_enabled ? [1] : []
    content {
      # External ingress
      # true: Accessible from public internet
      # false: Internal only (requires VNet integration)
      external_enabled = var.ingress_external_enabled

      # Port your application listens on
      target_port = var.ingress_target_port

      # Transport protocol
      # - http: HTTP/1.1
      # - http2: HTTP/2 with gRPC support
      # - tcp: Raw TCP (no HTTP features)
      transport = var.ingress_transport

      # Insecure connections
      # false: Redirect HTTP to HTTPS (recommended)
      # true: Allow HTTP (not recommended for production)
      allow_insecure_connections = var.allow_insecure_connections

      # Traffic weight configuration
      # Used for blue/green deployments and A/B testing
      traffic_weight {
        latest_revision = var.traffic_latest_revision
        percentage      = var.traffic_percentage
        label           = var.traffic_label
      }

      # IP security restrictions (optional)
      # Whitelist or blacklist specific IP ranges
      dynamic "ip_security_restriction" {
        for_each = var.ip_security_restrictions
        content {
          name             = ip_security_restriction.value.name
          ip_address_range = ip_security_restriction.value.ip_address_range
          action           = ip_security_restriction.value.action
          description      = ip_security_restriction.value.description
        }
      }

      # NOTE: CORS is not directly supported in azurerm_container_app ingress
      # Handle CORS at the application level (e.g., FastAPI middleware)
    }
  }

  # Registry configuration for private container registries
  # Authentication is handled via Managed Identity (RBAC)
  # The AcrPull role is assigned separately below
  # Note: For initial deployment, we temporarily use a public image to avoid
  # circular dependency. CI/CD will update with ACR image after managed identity exists.
  dynamic "registry" {
    for_each = var.registry_server != null ? [1] : []
    content {
      server   = var.registry_server
      identity = "system"
    }
  }

  # Secrets stored in Container App
  # Prefer using Key Vault SDK in application for secrets
  # These are primarily for non-sensitive configuration
  dynamic "secret" {
    for_each = var.secrets
    content {
      name  = secret.key
      value = secret.value
    }
  }

  # Dapr sidecar configuration (optional)
  # Enables distributed application runtime features
  dynamic "dapr" {
    for_each = var.dapr_enabled ? [1] : []
    content {
      app_id       = var.dapr_app_id
      app_protocol = var.dapr_app_protocol
      app_port     = var.dapr_app_port
    }
  }

  # Resource tags for organization and cost management
  tags = var.tags

  # Lifecycle management
  lifecycle {
    # Prevent accidental destruction of production container apps
    # Uncomment for production environments
    # prevent_destroy = true

    # Ignore changes managed by CI/CD pipeline:
    # - revision_suffix: CI/CD creates new revisions
    # - container image: CI/CD updates image tags via az containerapp update
    # - transport: Azure may auto-adjust ingress transport settings
    ignore_changes = [
      template[0].revision_suffix,
      template[0].container[0].image,
      ingress[0].transport
    ]

    # Preconditions: Validate configuration before apply
    precondition {
      condition     = var.min_replicas <= var.max_replicas
      error_message = "min_replicas (${var.min_replicas}) must be less than or equal to max_replicas (${var.max_replicas})."
    }

    precondition {
      condition     = var.container_cpu >= 0.25 && var.container_cpu <= 2.0
      error_message = "Container CPU must be between 0.25 and 2.0 vCPU."
    }

    precondition {
      condition     = var.ingress_target_port > 0 && var.ingress_target_port <= 65535
      error_message = "Ingress target port must be a valid port number (1-65535)."
    }
  }
}

#------------------------------------------------------------------------------
# RBAC: ACR Pull Access (Optional)
#------------------------------------------------------------------------------
# Grants the Container App's managed identity the AcrPull role on the
# container registry. This allows the app to pull images without credentials.
# Azure handles authentication automatically using the managed identity.
#------------------------------------------------------------------------------
resource "azurerm_role_assignment" "acr_pull" {
  count = var.enable_acr_pull ? 1 : 0

  # Scope: The container registry resource
  scope = var.container_registry_id

  # Role: AcrPull
  # Allows pulling images from the registry
  role_definition_name = "AcrPull"

  # Principal: The container app's managed identity
  principal_id = azurerm_container_app.this.identity[0].principal_id
}

#------------------------------------------------------------------------------
# RBAC: Key Vault Secrets Access (Optional)
#------------------------------------------------------------------------------
# Grants the Container App's managed identity the Key Vault Secrets User role.
# This allows the application to read secrets from Key Vault at runtime
# using the Azure SDK or REST API.
#------------------------------------------------------------------------------
resource "azurerm_role_assignment" "keyvault_secrets_user" {
  count = var.enable_key_vault_access ? 1 : 0

  # Scope: The Key Vault resource
  scope = var.key_vault_id

  # Role: Key Vault Secrets User
  # Allows reading secrets (not keys or certificates)
  role_definition_name = "Key Vault Secrets User"

  # Principal: The container app's managed identity
  principal_id = azurerm_container_app.this.identity[0].principal_id
}
