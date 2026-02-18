#------------------------------------------------------------------------------
# Private Endpoints Module - variables.tf
#------------------------------------------------------------------------------
# Input variable definitions for the private-endpoints module.
# This module provisions private endpoints and Private DNS zones for:
#   - Azure Key Vault  (privatelink.vaultcore.azure.net)
#   - Azure Container Registry (privatelink.azurecr.io)
#------------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Name of the resource group where endpoints will be created"
  type        = string
}

variable "location" {
  description = "Azure region for the private endpoints"
  type        = string
}

variable "environment" {
  description = "Short environment name used in resource naming (e.g. dev, staging, prod)"
  type        = string
}

variable "vnet_id" {
  description = "Resource ID of the Virtual Network to link the Private DNS zones to"
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "Resource ID of the subnet that hosts private endpoints (must have private_endpoint_network_policies_enabled = false)"
  type        = string
}

variable "key_vault_id" {
  description = "Resource ID of the Key Vault to expose via a private endpoint"
  type        = string
}

variable "container_registry_id" {
  description = "Resource ID of the Container Registry to expose via a private endpoint (SKU must be Standard or Premium)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all private endpoint resources"
  type        = map(string)
  default     = {}
}
