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

  # Container image - using ACR image
  # Domain service name: applicant-validator (DDD - describes domain capability)
  container_image = "${module.container_registry.login_server}/applicant-validator:latest"
}

# Resource Group
# Logical container for all Azure resources
# Wait for provider registration to complete before creating any resources
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

  # SKU: Standard required for private endpoints (Basic does not support them).
  # When enable_private_endpoints = false, Basic is used to minimise cost (~$0/mo).
  # When enable_private_endpoints = true,  Standard is used (~$20/mo).
  sku = var.enable_private_endpoints ? "Standard" : "Basic"

  # Public access: disabled when private endpoints are active
  public_network_access_enabled = !var.enable_private_endpoints

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

  # Public access: disabled when private endpoints are active
  public_network_access_enabled = !var.enable_private_endpoints

  # Network ACLs restrict which IPs can reach Key Vault directly.
  # bypass = "AzureServices" ensures the Container App managed identity can
  # always reach Key Vault even when default_action = "Deny".
  # Add pipeline agent or developer IPs to kv_allowed_ips to allow Terraform
  # operations from outside Azure (e.g. local runs, self-hosted agents).
  network_acls_enabled        = true
  network_acls_bypass         = "AzureServices"
  network_acls_default_action = "Deny"
  allowed_ip_ranges           = var.kv_allowed_ips

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

  # VNet integration: null = Azure-managed network; subnet ID = VNet injection (private endpoints).
  # one() safely returns null when module.networking has count = 0 (private endpoints disabled).
  infrastructure_subnet_id = one(module.networking[*].container_app_subnet_id)

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
  # Now enabled - managed identity exists and can pull from ACR
  registry_server       = module.container_registry.login_server
  enable_acr_pull       = true
  container_registry_id = module.container_registry.id

  # Key Vault RBAC access
  enable_key_vault_access = true
  key_vault_id            = module.key_vault.id

  # IP security restrictions (Item 1: Network Restrictions)
  # A single Allow 0.0.0.0/0 rule demonstrates the feature without blocking any traffic.
  # Replace with specific Cloudflare IP ranges or corporate egress IPs for real enforcement.
  ip_security_restrictions = [
    {
      name             = "allow-all"
      ip_address_range = "0.0.0.0/0"
      action           = "Allow"
      description      = "Allow all — replace with specific IP ranges (e.g. Cloudflare) in production"
    }
  ]

  # Azure AD EasyAuth (Item 2: Azure AD Authentication)
  # Set aad_client_id to enable token validation on /api/v1/validate.
  # /health and /ready are excluded so probes and smoke tests remain unauthenticated.
  aad_client_id = var.aad_client_id

  # Custom domain and certificate configuration
  # Certificate must be uploaded manually via: scripts/upload-certificate.sh
  custom_domain_enabled = var.custom_domain_enabled
  custom_domain_name    = var.custom_domain_name
  certificate_name      = var.certificate_name

  tags = local.common_tags

  # Ensure observability stack is created first.
  # When private endpoints are enabled, networking must also be ready so the
  # Container App environment can be injected into the VNet.
  depends_on = [
    module.observability,
    module.container_registry,
    module.key_vault,
    module.networking,
  ]
}

#------------------------------------------------------------------------------
# VNet + Subnets (Item 3: Private Endpoints)
#------------------------------------------------------------------------------
# Created only when enable_private_endpoints = true.
# Provides:
#   - A dedicated subnet for private endpoints (Key Vault, ACR)
#   - A delegated subnet for Container App environment VNet injection
#------------------------------------------------------------------------------
module "networking" {
  count  = var.enable_private_endpoints ? 1 : 0
  source = "../../modules/networking"

  vnet_name           = "vnet-${local.naming_prefix}"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location

  # Address spaces — adjust to avoid overlap with on-premises or other VNets
  vnet_address_space           = "10.0.0.0/16"
  private_endpoint_subnet_cidr = "10.0.1.0/24"
  container_app_subnet_cidr    = "10.0.2.0/23" # /23 minimum required by Azure Container Apps

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# Private Endpoints for Key Vault and ACR (Item 3: Private Endpoints)
#------------------------------------------------------------------------------
# Created only when enable_private_endpoints = true.
# Each endpoint gets a Private DNS zone linked to the VNet so that internal
# DNS lookups resolve to the private IP rather than the public endpoint.
#
# IMPORTANT — pipeline agent requirement:
#   Once public access is disabled on Key Vault and ACR, the CI/CD pipeline
#   agent must be on the same VNet (or peered / VPN-connected) to reach them.
#   Options:
#     1. Point-to-Site VPN Gateway from the self-hosted agent machine
#     2. Move the self-hosted agent to a VM inside this VNet
#     3. Use kv_allowed_ips to keep public access for specific agent IPs (Item 1)
#------------------------------------------------------------------------------
module "private_endpoints" {
  count  = var.enable_private_endpoints ? 1 : 0
  source = "../../modules/private-endpoints"

  resource_group_name        = module.resource_group.name
  location                   = module.resource_group.location
  environment                = local.environment
  vnet_id                    = module.networking[0].vnet_id
  private_endpoint_subnet_id = module.networking[0].private_endpoint_subnet_id
  key_vault_id               = module.key_vault.id
  container_registry_id      = module.container_registry.id

  tags = local.common_tags

  depends_on = [
    module.networking,
    module.key_vault,
    module.container_registry,
  ]
}
