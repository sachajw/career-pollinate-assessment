# Container Registry Module - Complete Example
# This example demonstrates all configuration options

# First, create a resource group
module "resource_group" {
  source = "../../resource-group"

  name     = "rg-acr-example"
  location = "eastus2"

  tags = {
    Environment = "dev"
    Project     = "terraform-modules"
  }
}

# Create Log Analytics for diagnostics (optional but recommended)
resource "azurerm_log_analytics_workspace" "example" {
  name                = "log-acr-example"
  location            = module.resource_group.location
  resource_group_name = module.resource_group.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# Create the Container Registry
module "container_registry" {
  source = "../.."

  name                = "acrexamplecomplete"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location

  # SKU Configuration
  sku = "Basic" # Options: Basic, Standard, Premium

  # Network Access
  public_network_access_enabled = true # Set to false for private endpoints (Premium only)

  # Retention Policy (Premium only)
  retention_enabled = false
  retention_days    = 7

  # Content Trust (Premium only)
  trust_policy_enabled = false

  # Diagnostic Logging
  log_analytics_workspace_id = azurerm_log_analytics_workspace.example.id

  tags = {
    Environment = "dev"
    Project     = "terraform-modules"
    ManagedBy   = "terraform"
  }
}

# Outputs
output "registry_id" {
  description = "The ID of the container registry"
  value       = module.container_registry.id
}

output "registry_name" {
  description = "The name of the container registry"
  value       = module.container_registry.name
}

output "registry_login_server" {
  description = "The login server URL"
  value       = module.container_registry.login_server
}
