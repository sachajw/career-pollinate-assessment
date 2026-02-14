#------------------------------------------------------------------------------
# Azure Key Vault Module - outputs.tf
#------------------------------------------------------------------------------
# Output definitions for the Key Vault module.
# These outputs are used by dependent modules (Container Apps, applications)
# and for integration purposes.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Key Vault Identification Outputs
#------------------------------------------------------------------------------

# id - The Azure Resource Manager ID of the Key Vault
# Used for RBAC role assignments and resource references
output "id" {
  description = "The ID of the Key Vault"
  value       = azurerm_key_vault.this.id
}

# name - The name of the Key Vault
# Used in scripts and for display purposes
output "name" {
  description = "The name of the Key Vault"
  value       = azurerm_key_vault.this.name
}

# vault_uri - The URI for accessing the Key Vault
# Used by applications to connect to Key Vault
# Format: https://<vault-name>.vault.azure.net/
output "vault_uri" {
  description = "The URI of the Key Vault"
  value       = azurerm_key_vault.this.vault_uri
}

#------------------------------------------------------------------------------
# Tenant and Resource Information
#------------------------------------------------------------------------------

# tenant_id - The Azure AD tenant ID for the Key Vault
# Used for authentication configuration
output "tenant_id" {
  description = "The Azure Active Directory tenant ID for the Key Vault"
  value       = azurerm_key_vault.this.tenant_id
}

# resource_id - The Azure Resource Manager ID (alias for id)
# Provided for compatibility with different naming conventions
output "resource_id" {
  description = "The Azure Resource Manager ID of the Key Vault"
  value       = azurerm_key_vault.this.id
}
