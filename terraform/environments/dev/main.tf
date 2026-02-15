# Development Environment Configuration
# This file orchestrates all modules for the dev environment

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Local variables for naming convention and common tags
locals {
  environment = var.environment
  project     = var.project_name
  location    = var.location

  # Naming convention: {resource_type}-{project}-{environment}
  # Example: rg-riskscoring-dev, kv-riskscoring-dev
  naming_prefix = "${local.project}-${local.environment}"

  # Common tags applied to all resources
  common_tags = merge(
    {
      Environment = local.environment
      Project     = local.project
      ManagedBy   = "Terraform"
      CostCenter  = "Engineering"
      Owner       = "Platform Team"
      Compliance  = "SOC2"
    },
    var.tags # Allow additional tags from variables
  )

  # Container image from ACR (placeholder, will be updated by CI/CD)
  # Domain service name: applicant-validator (DDD - describes domain capability)
  container_image = "${module.container_registry.login_server}/applicant-validator:latest"
}

# Resource Group
# Logical container for all Azure resources
module "resource_group" {
  source = "../../modules/resource-group"

  name     = "rg-${local.naming_prefix}"
  location = local.location
  tags     = local.common_tags
}

# Observability Stack (Log Analytics + Application Insights)
# Must be created before Container App (required for logging)
module "observability" {
  source = "../../modules/observability"

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location

  # Log Analytics configuration
  log_analytics_name           = "log-${local.naming_prefix}"
  log_analytics_sku            = "PerGB2018"
  log_analytics_retention_days = var.log_analytics_retention_days
  log_analytics_daily_quota_gb = 5 # Cap at 5GB/day to prevent cost overruns

  # Application Insights configuration
  app_insights_name         = "appi-${local.naming_prefix}"
  application_type          = "web"
  sampling_percentage       = 100 # Dev: 100% sampling for full visibility
  app_insights_daily_cap_gb = 2   # Cap at 2GB/day

  # Dev settings: Enable for easier debugging
  disable_ip_masking            = true  # Show full IPs for debugging
  local_authentication_disabled = false # Allow API key auth for dev
  internet_ingestion_enabled    = true
  internet_query_enabled        = true

  # Availability test (optional, useful for dev)
  create_availability_test = var.enable_availability_test

  tags = local.common_tags
}

# Container Registry
# Private Docker registry for container images
module "container_registry" {
  source = "../../modules/container-registry"

  # ACR names must be globally unique and alphanumeric only
  name                = "acr${replace(local.naming_prefix, "-", "")}" # Remove hyphens
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location

  # Dev: Basic SKU (no geo-replication, no premium features)
  sku = "Basic"

  # Dev: Public access enabled (no private endpoint)
  public_network_access_enabled = true

  # Retention and trust policies (Premium only)
  retention_enabled    = false
  trust_policy_enabled = false

  # Enable diagnostics
  log_analytics_workspace_id = module.observability.log_analytics_workspace_id

  tags = local.common_tags
}

# Key Vault
# Secure storage for secrets (API keys, connection strings, etc.)
module "key_vault" {
  source = "../../modules/key-vault"

  # Key Vault names must be globally unique, 3-24 chars
  name                = "kv-${local.naming_prefix}"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location

  # Standard SKU (Premium supports HSM-backed keys)
  sku_name = "standard"

  # Soft delete enabled for data protection
  soft_delete_retention_days = 90
  purge_protection_enabled   = true # Prevent accidental permanent deletion

  # Dev: Public access enabled (no private endpoint)
  public_network_access_enabled = true

  # Dev: No network ACLs (allow all Azure services)
  network_acls_enabled = false

  # Grant current deployer admin access for initial setup
  deployer_object_id = data.azurerm_client_config.current.object_id

  # Enable diagnostics for audit logging
  log_analytics_workspace_id = module.observability.log_analytics_workspace_id

  # Secrets: These should be added separately via CI/CD or manually
  # This is just a placeholder - DO NOT commit real secrets here
  secrets = {
    # RISKSHIELD-API-KEY will be added via:
    # az keyvault secret set --vault-name kv-riskscoring-dev --name RISKSHIELD-API-KEY --value <actual-key>
  }

  tags = local.common_tags
}

# Container App
# The actual application deployment
module "container_app" {
  source = "../../modules/container-app"

  name                = "ca-${local.naming_prefix}"
  environment_name    = "cae-${local.naming_prefix}"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location

  # Link to Log Analytics for logging
  log_analytics_workspace_id = module.observability.log_analytics_workspace_id

  # Dev: No VNet integration (Azure-managed network)
  infrastructure_subnet_id = null

  # Dev: Public ingress
  internal_load_balancer_enabled = false

  # Dev: No zone redundancy
  zone_redundancy_enabled = false

  # Container configuration
  # Domain service name describes business capability (DDD)
  container_name   = "applicant-validator"
  container_image  = local.container_image
  container_cpu    = 0.5   # 0.5 vCPU
  container_memory = "1Gi" # 1GB RAM

  # Dev: Scale to zero to save costs when not in use
  # Note: This causes ~2-3s cold start on first request
  min_replicas = var.container_app_min_replicas
  max_replicas = var.container_app_max_replicas

  # HTTP-based autoscaling
  http_scale_rule_enabled        = true
  http_scale_concurrent_requests = 100 # Scale out at 100 concurrent requests

  # Environment variables (non-sensitive)
  environment_variables = {
    ENVIRONMENT                           = local.environment
    LOG_LEVEL                             = "INFO"
    PORT                                  = "8080"
    KEY_VAULT_URL                         = module.key_vault.vault_uri
    APPLICATIONINSIGHTS_CONNECTION_STRING = module.observability.app_insights_connection_string
  }

  # Health probes
  liveness_probe_enabled  = true
  liveness_probe_path     = "/health"
  liveness_probe_port     = 8080
  liveness_probe_interval = 30

  readiness_probe_enabled  = true
  readiness_probe_path     = "/ready"
  readiness_probe_port     = 8080
  readiness_probe_interval = 10

  # Ingress configuration
  ingress_enabled            = true
  ingress_external_enabled   = true # Public internet access
  ingress_target_port        = 8080
  ingress_transport          = "http"
  allow_insecure_connections = false # HTTPS only

  # Traffic routing (100% to latest revision)
  traffic_latest_revision = true
  traffic_percentage      = 100

  # NOTE: CORS is handled at the application level (FastAPI middleware)
  # The azurerm_container_app resource does not support CORS configuration

  # Container registry configuration
  registry_server       = module.container_registry.login_server
  enable_acr_pull       = true
  container_registry_id = module.container_registry.id

  # Key Vault RBAC access
  enable_key_vault_access = true
  key_vault_id            = module.key_vault.id

  tags = local.common_tags

  # Ensure observability stack is created first
  depends_on = [
    module.observability,
    module.container_registry,
    module.key_vault
  ]
}
