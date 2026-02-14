# Key Vault Module Outputs

output "id" {
  description = "The ID of the Key Vault"
  value       = azurerm_key_vault.this.id
}

output "name" {
  description = "The name of the Key Vault"
  value       = azurerm_key_vault.this.name
}

output "vault_uri" {
  description = "The URI of the Key Vault"
  value       = azurerm_key_vault.this.vault_uri
}

output "tenant_id" {
  description = "The Azure Active Directory tenant ID for the Key Vault"
  value       = azurerm_key_vault.this.tenant_id
}

output "resource_id" {
  description = "The Azure Resource Manager ID of the Key Vault"
  value       = azurerm_key_vault.this.id
}
