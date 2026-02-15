#------------------------------------------------------------------------------
# Azure DevOps Module Variables
#------------------------------------------------------------------------------

variable "project_id" {
  description = "Azure DevOps project ID"
  type        = string
}

variable "project_name" {
  description = "Project name for naming resources"
  type        = string
  default     = "finrisk"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "service_connection_name" {
  description = "Base name for service connections"
  type        = string
  default     = "finrisk"
}

# GitHub Configuration
variable "repository" {
  description = "GitHub repository (owner/repo)"
  type        = string
}

variable "branch" {
  description = "Default branch"
  type        = string
  default     = "main"
}

variable "pipeline_yaml_path" {
  description = "Path to Azure Pipelines YAML file"
  type        = string
  default     = "/pipelines/azure-pipelines.yml"
}

# Azure Configuration
variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "subscription_name" {
  description = "Azure subscription name"
  type        = string
}

variable "resource_group_name" {
  description = "Azure resource group name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "container_registry_name" {
  description = "Azure Container Registry name"
  type        = string
}

variable "container_app_name" {
  description = "Azure Container App name"
  type        = string
}

variable "key_vault_name" {
  description = "Azure Key Vault name"
  type        = string
}

# Azure Service Principal Credentials
variable "azure_client_id" {
  description = "Azure AD App Client ID"
  type        = string
  sensitive   = true
}

variable "azure_client_secret" {
  description = "Azure AD App Client Secret"
  type        = string
  sensitive   = true
}

variable "azure_tenant_id" {
  description = "Azure AD Tenant ID"
  type        = string
  sensitive   = true
}

# Application Secrets
variable "riskshield_api_key" {
  description = "RiskShield API key"
  type        = string
  sensitive   = true
  default     = ""
}
