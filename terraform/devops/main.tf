#------------------------------------------------------------------------------
# Azure DevOps Environment Configuration
#------------------------------------------------------------------------------
# Configures Azure DevOps to connect with GitHub and Azure
# Run this after initial infrastructure deployment
#------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = "~> 1.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }

  # Backend for state storage (use same storage as infrastructure)
  backend "azurerm" {
    # Configure via backend.hcl
  }
}

#------------------------------------------------------------------------------
# Providers
#------------------------------------------------------------------------------
# Reads credentials from environment variables:
# - AZDO_ORG_SERVICE_URL
# - AZDO_PERSONAL_ACCESS_TOKEN
# - ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID
#------------------------------------------------------------------------------
provider "azuredevops" {
  org_service_url       = var.azuredevops_org_service_url
  personal_access_token = var.azuredevops_pat
}

provider "azurerm" {
  features {}

  # Uses ARM_* environment variables automatically
  subscription_id = var.azure_subscription_id
}

#------------------------------------------------------------------------------
# Data Sources - Get Infrastructure Info
#------------------------------------------------------------------------------
data "azurerm_resource_group" "finrisk" {
  name = "rg-finrisk-${var.environment}"
}

data "azurerm_container_registry" "finrisk" {
  name                = "acrfinrisk${var.environment}"
  resource_group_name = data.azurerm_resource_group.finrisk.name
}

data "azurerm_container_app" "finrisk" {
  name                = "ca-finrisk-${var.environment}"
  resource_group_name = data.azurerm_resource_group.finrisk.name
}

data "azurerm_key_vault" "finrisk" {
  name                = "kv-finrisk-${var.environment}"
  resource_group_name = data.azurerm_resource_group.finrisk.name
}

data "azurerm_subscription" "current" {}

#------------------------------------------------------------------------------
# Local Variables
#------------------------------------------------------------------------------
locals {
  repository = "${split("/", var.github_repository_url)[3]}/${split("/", var.github_repository_url)[4]}"
}

#------------------------------------------------------------------------------
# Azure DevOps Module
#------------------------------------------------------------------------------
module "azure_devops" {
  source = "../modules/azure-devops"

  # Azure DevOps Configuration
  project_id             = var.azuredevops_project_id
  project_name           = var.project_name
  environment            = var.environment
  service_connection_name = "${var.project_name}-${var.environment}"

  # GitHub Configuration
  repository            = local.repository
  branch                = var.branch
  pipeline_yaml_path    = var.pipeline_yaml_path

  # Azure Configuration
  subscription_id       = data.azurerm_subscription.current.subscription_id
  subscription_name     = data.azurerm_subscription.current.display_name
  resource_group_name   = data.azurerm_resource_group.finrisk.name
  location              = data.azurerm_resource_group.finrisk.location
  container_registry_name = data.azurerm_container_registry.finrisk.name
  container_app_name    = data.azurerm_container_app.finrisk.name
  key_vault_name        = data.azurerm_key_vault.finrisk.name

  # Azure Service Principal (from variables)
  azure_client_id       = var.azure_client_id
  azure_client_secret   = var.azure_client_secret
  azure_tenant_id       = var.azure_tenant_id

  # Application Secrets
  riskshield_api_key    = var.riskshield_api_key
}
