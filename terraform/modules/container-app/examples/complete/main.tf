# Container App Module - Complete Example
# This example demonstrates all configuration options

# Get current client configuration
data "azurerm_client_config" "current" {}

# First, create a resource group
module "resource_group" {
  source = "../../resource-group"

  name     = "rg-ca-example"
  location = "eastus2"

  tags = {
    Environment = "dev"
    Project     = "terraform-modules"
  }
}

# Create Log Analytics for logging
resource "azurerm_log_analytics_workspace" "example" {
  name                = "log-ca-example"
  location            = module.resource_group.location
  resource_group_name = module.resource_group.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# Create Application Insights for APM
resource "azurerm_application_insights" "example" {
  name                = "appi-ca-example"
  location            = module.resource_group.location
  resource_group_name = module.resource_group.name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.example.id
}

# Create a Container Registry
module "container_registry" {
  source = "../../container-registry"

  name                = "acrcacomplete"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  sku                 = "Basic"

  log_analytics_workspace_id = azurerm_log_analytics_workspace.example.id

  tags = {
    Environment = "dev"
  }
}

# Create a Key Vault
module "key_vault" {
  source = "../../key-vault"

  name                = "kv-ca-complete"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  sku_name            = "standard"

  deployer_object_id         = data.azurerm_client_config.current.object_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.example.id

  tags = {
    Environment = "dev"
  }
}

# Create the Container App
module "container_app" {
  source = "../.."

  name                = "ca-example"
  environment_name    = "cae-example"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location

  # Environment Configuration
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.example.id
  infrastructure_subnet_id       = null  # Set for VNet integration
  internal_load_balancer_enabled = false # Set to true for private ingress
  zone_redundancy_enabled        = false # Set to true for production

  # Container Configuration
  container_name   = "api"
  container_image  = "${module.container_registry.login_server}/example-api:latest"
  container_cpu    = 0.5
  container_memory = "1Gi"

  # Revision Mode
  revision_mode = "Single" # Options: Single, Multiple (for blue/green)

  # Scaling Configuration
  min_replicas = 0 # Scale to zero for dev
  max_replicas = 5

  http_scale_rule_enabled        = true
  http_scale_concurrent_requests = 100

  # Environment Variables
  environment_variables = {
    ENVIRONMENT   = "dev"
    LOG_LEVEL     = "INFO"
    PORT          = "8080"
    KEY_VAULT_URL = module.key_vault.vault_uri
  }

  # Health Probes
  liveness_probe_enabled  = true
  liveness_probe_path     = "/health"
  liveness_probe_port     = 8080
  liveness_probe_interval = 30

  readiness_probe_enabled  = true
  readiness_probe_path     = "/ready"
  readiness_probe_port     = 8080
  readiness_probe_interval = 10

  # Ingress Configuration
  ingress_enabled            = true
  ingress_external_enabled   = true
  ingress_target_port        = 8080
  ingress_transport          = "http"
  allow_insecure_connections = false

  # Traffic Routing
  traffic_latest_revision = true
  traffic_percentage      = 100

  # NOTE: CORS should be handled at the application level (e.g., FastAPI middleware)
  # The azurerm_container_app resource does not support CORS configuration

  # Registry Configuration
  registry_server       = module.container_registry.login_server
  enable_acr_pull       = true
  container_registry_id = module.container_registry.id

  # Key Vault Access
  enable_key_vault_access = true
  key_vault_id            = module.key_vault.id

  tags = {
    Environment = "dev"
    Project     = "terraform-modules"
    ManagedBy   = "terraform"
  }

  depends_on = [
    module.container_registry,
    module.key_vault
  ]
}

# Outputs
output "container_app_id" {
  description = "The ID of the container app"
  value       = module.container_app.id
}

output "container_app_name" {
  description = "The name of the container app"
  value       = module.container_app.name
}

output "application_url" {
  description = "The full HTTPS URL of the application"
  value       = module.container_app.application_url
}

output "identity_principal_id" {
  description = "The principal ID of the managed identity"
  value       = module.container_app.identity_principal_id
}

output "environment_id" {
  description = "The ID of the container app environment"
  value       = module.container_app.environment_id
}
