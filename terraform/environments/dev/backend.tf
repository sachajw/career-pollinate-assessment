# Terraform Backend Configuration
# Stores Terraform state in Azure Storage for team collaboration and state locking
#
# Prerequisites:
# 1. Create Azure Storage Account for Terraform state:
#    az group create --name rg-terraform-state --location eastus2
#    az storage account create --name stterraformstate<unique> --resource-group rg-terraform-state --location eastus2 --sku Standard_LRS
#    az storage container create --name tfstate --account-name stterraformstate<unique>
#
# 2. Initialize Terraform with backend:
#    terraform init \
#      -backend-config="storage_account_name=stterraformstate<unique>" \
#      -backend-config="container_name=tfstate" \
#      -backend-config="key=riskscoring-dev.tfstate"
#
# OR use backend.hcl file:
#    terraform init -backend-config=backend.hcl

terraform {
  backend "azurerm" {
    # Storage account name (set via -backend-config or backend.hcl)
    # storage_account_name = "stterraformstate<unique>"

    # Container name for state files
    # container_name = "tfstate"

    # State file name (unique per environment)
    # key = "riskscoring-dev.tfstate"

    # Resource group containing the storage account
    # resource_group_name = "rg-terraform-state"

    # Use storage account access key or Azure AD authentication
    # use_azuread_auth = true (recommended, requires Storage Blob Data Contributor role)
    # use_msi = true (for CI/CD with managed identity)
  }
}

# Note: Backend configuration values are not interpolated, so they must be set via:
# 1. Command line: terraform init -backend-config="key=value"
# 2. Backend config file: terraform init -backend-config=backend.hcl
# 3. Environment variables: ARM_ACCESS_KEY, ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_SUBSCRIPTION_ID, ARM_TENANT_ID
