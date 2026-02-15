#------------------------------------------------------------------------------
# Azure DevOps Environment Variables
#------------------------------------------------------------------------------

# Azure DevOps Configuration
variable "azuredevops_org_service_url" {
  description = "Azure DevOps organization URL (e.g., https://dev.azure.com/your-org)"
  type        = string
  default     = env("AZDO_ORG_SERVICE_URL")
}

variable "azuredevops_pat" {
  description = "Azure DevOps Personal Access Token"
  type        = string
  sensitive   = true
  default     = env("AZDO_PERSONAL_ACCESS_TOKEN")
}

variable "azuredevops_project_id" {
  description = "Azure DevOps project ID"
  type        = string
  default     = env("AZDO_PROJECT_ID")
}

variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
  default     = env("ARM_SUBSCRIPTION_ID")
}

# Project Configuration
variable "project_name" {
  description = "Project name"
  type        = string
  default     = "finrisk"
}

variable "environment" {
  description = "Environment"
  type        = string
  default     = "dev"
}

variable "branch" {
  description = "Git branch to trigger builds"
  type        = string
  default     = "main"
}

variable "pipeline_yaml_path" {
  description = "Path to Azure Pipelines YAML"
  type        = string
  default     = "/pipelines/azure-pipelines.yml"
}

# GitHub Configuration
variable "github_repository_url" {
  description = "GitHub repository URL (e.g., https://github.com/owner/repo)"
  type        = string
  default     = env("GITHUB_REPOSITORY_URL")
}

# Azure Service Principal
variable "azure_client_id" {
  description = "Azure AD App Client ID for deployments"
  type        = string
  sensitive   = true
  default     = env("ARM_CLIENT_ID")
}

variable "azure_client_secret" {
  description = "Azure AD App Client Secret for deployments"
  type        = string
  sensitive   = true
  default     = env("ARM_CLIENT_SECRET")
}

variable "azure_tenant_id" {
  description = "Azure AD Tenant ID"
  type        = string
  sensitive   = true
  default     = env("ARM_TENANT_ID")
}

# Application Secrets
variable "riskshield_api_key" {
  description = "RiskShield API key"
  type        = string
  sensitive   = true
  default     = ""
}
