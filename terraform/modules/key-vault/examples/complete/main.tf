# Key Vault Module - Complete Example
# This example demonstrates all configuration options

# Get current client configuration for RBAC assignment
data "azurerm_client_config" "current" {}

# First, create a resource group
module "resource_group" {
  source = "../../resource-group"

  name     = "rg-kv-example"
  location = "eastus2"

  tags = {
    Environment = "dev"
    Project     = "terraform-modules"
  }
}

# Create Log Analytics for diagnostics (optional but recommended)
resource "azurerm_log_analytics_workspace" "example" {
  name                = "log-kv-example"
  location            = module.resource_group.location
  resource_group_name = module.resource_group.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# Create the Key Vault
module "key_vault" {
  source = "../.."

  name                = "kv-example-complete"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location

  # SKU Configuration
  sku_name = "standard" # Options: standard, premium (for HSM keys)

  # Data Protection
  soft_delete_retention_days = 90
  purge_protection_enabled   = true

  # Network Access
  public_network_access_enabled = true # Set to false with private endpoint for production

  # Network ACLs (optional, for production)
  network_acls_enabled        = false
  network_acls_default_action = "Deny"
  network_acls_bypass         = "AzureServices"

  # RBAC Assignment for deployer
  deployer_object_id = data.azurerm_client_config.current.object_id

  # Diagnostic Logging
  log_analytics_workspace_id = azurerm_log_analytics_workspace.example.id

  # Initial secrets (use with caution - prefer external injection)
  # secrets = {
  #   "EXAMPLE-SECRET" = "example-value"
  # }

  tags = {
    Environment = "dev"
    Project     = "terraform-modules"
    ManagedBy   = "terraform"
  }
}

# Outputs
output "key_vault_id" {
  description = "The ID of the Key Vault"
  value       = module.key_vault.id
}

output "key_vault_name" {
  description = "The name of the Key Vault"
  value       = module.key_vault.name
}

output "key_vault_uri" {
  description = "The URI of the Key Vault"
  value       = module.key_vault.vault_uri
}
