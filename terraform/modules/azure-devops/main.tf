#------------------------------------------------------------------------------
# Azure DevOps Terraform Configuration
#------------------------------------------------------------------------------
# Manages Azure DevOps resources:
# - GitHub service connection
# - Variable groups for secrets
# - Build pipeline
#------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = "~> 1.0"
    }
  }
}

#------------------------------------------------------------------------------
# GitHub Service Connection (OAuth)
#------------------------------------------------------------------------------
# Uses OAuth authorization - you'll authorize during terraform apply
resource "azuredevops_serviceendpoint_github" "github" {
  project_id            = var.project_id
  service_endpoint_name = "${var.service_connection_name}-github"
  description           = "GitHub connection for ${var.repository}"

  # OAuth - triggers authorization flow during apply
  auth_oauth {}
}

#------------------------------------------------------------------------------
# Azure Resource Manager Service Connection
#------------------------------------------------------------------------------
# Authenticates Azure DevOps with Azure for deployments
resource "azuredevops_serviceendpoint_azurecr" "acr" {
  project_id                = var.project_id
  service_endpoint_name     = "${var.service_connection_name}-acr"
  resource_group            = var.resource_group_name
  azurecr_name              = var.container_registry_name
  azurecr_subscription_id   = var.subscription_id
  azurecr_subscription_name = var.subscription_name
}

#------------------------------------------------------------------------------
# Azure RM Service Connection (for Terraform deployments)
#------------------------------------------------------------------------------
resource "azuredevops_serviceendpoint_azurerm" "azurerm" {
  project_id            = var.project_id
  service_endpoint_name = "${var.service_connection_name}-azurerm"
  credentials {
    serviceprincipalid  = var.azure_client_id
    serviceprincipalkey = var.azure_client_secret
  }
  azurecr_spn_tenantid      = var.azure_tenant_id
  azurecr_subscription_id   = var.subscription_id
  azurecr_subscription_name = var.subscription_name
}

#------------------------------------------------------------------------------
# Variable Group - Infrastructure
#------------------------------------------------------------------------------
# Non-secret variables for infrastructure
resource "azuredevops_variable_group" "infrastructure" {
  project_id   = var.project_id
  name         = "${var.project_name}-infrastructure"
  description  = "Infrastructure configuration for ${var.project_name}"
  allow_access = true

  variable {
    name  = "RESOURCE_GROUP"
    value = var.resource_group_name
  }

  variable {
    name  = "LOCATION"
    value = var.location
  }

  variable {
    name  = "CONTAINER_REGISTRY"
    value = var.container_registry_name
  }

  variable {
    name  = "CONTAINER_APP_NAME"
    value = var.container_app_name
  }

  variable {
    name  = "KEY_VAULT_NAME"
    value = var.key_vault_name
  }

  variable {
    name  = "ENVIRONMENT"
    value = var.environment
  }
}

#------------------------------------------------------------------------------
# Variable Group - Secrets
#------------------------------------------------------------------------------
# Secret variables (Azure credentials)
resource "azuredevops_variable_group" "secrets" {
  project_id   = var.project_id
  name         = "${var.project_name}-secrets"
  description  = "Secret credentials for ${var.project_name}"
  allow_access = true

  variable {
    name         = "AZURE_CLIENT_ID"
    secret_value = var.azure_client_id
    is_secret    = true
  }

  variable {
    name         = "AZURE_CLIENT_SECRET"
    secret_value = var.azure_client_secret
    is_secret    = true
  }

  variable {
    name         = "AZURE_TENANT_ID"
    secret_value = var.azure_tenant_id
    is_secret    = true
  }

  variable {
    name         = "AZURE_SUBSCRIPTION_ID"
    secret_value = var.subscription_id
    is_secret    = true
  }

  variable {
    name         = "RISKSHIELD_API_KEY"
    secret_value = var.riskshield_api_key
    is_secret    = true
  }
}

#------------------------------------------------------------------------------
# Build Pipeline
#------------------------------------------------------------------------------
# GitHub-triggered CI/CD pipeline
resource "azuredevops_build_definition" "pipeline" {
  project_id = var.project_id
  name       = "${var.project_name}-ci-cd"
  path       = "\\${var.project_name}"

  repository {
    repo_type   = "GitHub"
    repo_id     = var.repository
    branch_name = var.branch
    yml_path    = var.pipeline_yaml_path
    service_connection_id = azuredevops_serviceendpoint_github.github.id
  }

  # Trigger on push to main
  ci_trigger {
    use_yaml = true
  }

  # Pull request validation
  pull_request_trigger {
    use_yaml = true
  }

  # Variable groups
  variable_groups = [
    azuredevops_variable_group.infrastructure.id,
    azuredevops_variable_group.secrets.id
  ]
}
