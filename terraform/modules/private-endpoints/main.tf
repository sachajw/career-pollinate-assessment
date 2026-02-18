#------------------------------------------------------------------------------
# Private Endpoints Module - main.tf
#------------------------------------------------------------------------------
# Provisions private endpoints for Key Vault and Azure Container Registry so
# that all service traffic stays on the VNet and never traverses the public
# internet. Each endpoint is paired with a Private DNS zone and a VNet link so
# that DNS lookups from inside the VNet resolve to the private IP address.
#
# Resources created per service:
#   - azurerm_private_dns_zone               (privatelink.* zone)
#   - azurerm_private_dns_zone_virtual_network_link
#   - azurerm_private_endpoint               (NIC + private IP)
#   - azurerm_private_dns_zone_group         (auto-registers DNS A record)
#
# Pre-requisites:
#   Key Vault  — public_network_access_enabled = false
#   ACR        — public_network_access_enabled = false, SKU >= Standard
#   Subnet     — private_endpoint_network_policies_enabled = false
#
# Usage:
#   module "private_endpoints" {
#     source                     = "../../modules/private-endpoints"
#     resource_group_name        = "rg-finrisk-dev"
#     location                   = "eastus2"
#     environment                = "dev"
#     vnet_id                    = module.networking.vnet_id
#     private_endpoint_subnet_id = module.networking.private_endpoint_subnet_id
#     key_vault_id               = module.key_vault.id
#     container_registry_id      = module.container_registry.id
#     tags                       = { Environment = "dev" }
#   }
#------------------------------------------------------------------------------

#==============================================================================
# Key Vault Private Endpoint
#==============================================================================

#------------------------------------------------------------------------------
# Private DNS Zone for Key Vault
#------------------------------------------------------------------------------
# All Azure Key Vault private endpoints must use the canonical zone name
# "privatelink.vaultcore.azure.net". Azure automatically registers an A record
# for the vault's FQDN when the private_dns_zone_group is attached.
#------------------------------------------------------------------------------
resource "azurerm_private_dns_zone" "keyvault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault" {
  name                  = "link-kv-${var.environment}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault.name
  virtual_network_id    = var.vnet_id

  # Auto-registration is for VM hostnames, not private endpoints
  registration_enabled = false

  tags = var.tags
}

#------------------------------------------------------------------------------
# Key Vault Private Endpoint
#------------------------------------------------------------------------------
resource "azurerm_private_endpoint" "keyvault" {
  name                = "pe-kv-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-kv-${var.environment}"
    private_connection_resource_id = var.key_vault_id
    # "vault" is the only supported sub-resource for Key Vault
    subresource_names    = ["vault"]
    is_manual_connection = false
  }

  # Attaching the DNS zone group causes Azure to automatically create the A
  # record in the Private DNS zone, pointing to the private IP of this endpoint.
  private_dns_zone_group {
    name                 = "dns-kv"
    private_dns_zone_ids = [azurerm_private_dns_zone.keyvault.id]
  }

  tags = var.tags
}

#==============================================================================
# Container Registry Private Endpoint
#==============================================================================

#------------------------------------------------------------------------------
# Private DNS Zone for ACR
#------------------------------------------------------------------------------
# All ACR private endpoints use "privatelink.azurecr.io".
# Note: ACR creates two private IPs per endpoint (registry + data).
# The private_dns_zone_group handles both A records automatically.
#------------------------------------------------------------------------------
resource "azurerm_private_dns_zone" "acr" {
  name                = "privatelink.azurecr.io"
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  name                  = "link-acr-${var.environment}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false

  tags = var.tags
}

#------------------------------------------------------------------------------
# ACR Private Endpoint
#------------------------------------------------------------------------------
resource "azurerm_private_endpoint" "acr" {
  name                = "pe-acr-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-acr-${var.environment}"
    private_connection_resource_id = var.container_registry_id
    # "registry" is the sub-resource for the ACR data plane
    subresource_names    = ["registry"]
    is_manual_connection = false
  }

  private_dns_zone_group {
    name                 = "dns-acr"
    private_dns_zone_ids = [azurerm_private_dns_zone.acr.id]
  }

  tags = var.tags
}
