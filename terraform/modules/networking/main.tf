#------------------------------------------------------------------------------
# Networking Module - main.tf
#------------------------------------------------------------------------------
# Creates a Virtual Network with two subnets to support private endpoints and
# Container App environment VNet injection.
#
# Subnet layout (defaults):
#   10.0.1.0/24  snet-private-endpoints  — Key Vault and ACR private endpoints
#   10.0.2.0/23  snet-container-app      — Container App environment injection
#                                          (/23 is the Azure minimum for this use)
#
# Usage:
#   module "networking" {
#     source              = "../../modules/networking"
#     vnet_name           = "vnet-finrisk-dev"
#     resource_group_name = "rg-finrisk-dev"
#     location            = "eastus2"
#     tags                = { Environment = "dev" }
#   }
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Virtual Network
#------------------------------------------------------------------------------
resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.vnet_address_space]

  tags = var.tags
}

#------------------------------------------------------------------------------
# Subnet: Private Endpoints
#------------------------------------------------------------------------------
# Hosts the private endpoints for Key Vault and ACR.
# private_endpoint_network_policies_enabled must be false to allow private
# endpoints to be placed in this subnet.
#------------------------------------------------------------------------------
resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.private_endpoint_subnet_cidr]

  # Required: disable endpoint network policies so private endpoints can be
  # provisioned in this subnet (Azure enforces this restriction).
  # NOTE: private_endpoint_network_policies_enabled is deprecated in AzureRM 3.x
  # and will be removed in 4.0. Update to private_endpoint_network_policies block
  # when upgrading to AzureRM 4.x.
  private_endpoint_network_policies_enabled = false
}

#------------------------------------------------------------------------------
# Subnet: Container App Environment
#------------------------------------------------------------------------------
# Delegated to Microsoft.App/environments for Container App VNet injection.
# Azure requires this subnet to be at least /23 (512 addresses).
#------------------------------------------------------------------------------
resource "azurerm_subnet" "container_app" {
  name                 = "snet-container-app"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.container_app_subnet_cidr]

  # Delegation: grants Microsoft.App/environments exclusive use of this subnet
  delegation {
    name = "Microsoft.App.environments"

    service_delegation {
      name = "Microsoft.App/environments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}
