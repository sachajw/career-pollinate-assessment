#------------------------------------------------------------------------------
# Networking Module - variables.tf
#------------------------------------------------------------------------------
# Input variable definitions for the networking module.
# This module creates a VNet with two subnets:
#   - A private-endpoints subnet for Key Vault and ACR private endpoints
#   - A Container App environment subnet for VNet injection
#------------------------------------------------------------------------------

variable "vnet_name" {
  description = "Name of the Virtual Network"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "vnet_address_space" {
  description = "Address space for the VNet in CIDR notation (e.g. 10.0.0.0/16)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_endpoint_subnet_cidr" {
  description = "CIDR block for the private endpoints subnet (e.g. 10.0.1.0/24)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "container_app_subnet_cidr" {
  description = "CIDR block for the Container App environment subnet. Azure requires /23 or larger for VNet-injected Container App Environments."
  type        = string
  default     = "10.0.2.0/23"
}

variable "tags" {
  description = "Tags to apply to all networking resources"
  type        = map(string)
  default     = {}
}
