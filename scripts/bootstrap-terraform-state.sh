#!/bin/bash
#==============================================================================
# Terraform State Bootstrap Script
#==============================================================================
# This script creates the Azure resources needed for Terraform remote state.
# Run this ONCE before using Terraform for the first time.
#
# Creates:
# - Resource Group: rg-terraform-state
# - Storage Account: sttfstatefinrisk<random>
# - Blob Container: tfstate
#
# Usage:
#   ./bootstrap-terraform-state.sh [LOCATION]
#
# Examples:
#   ./bootstrap-terraform-state.sh              # Uses eastus2
#   ./bootstrap-terraform-state.sh westus2      # Uses westus2
#
# Prerequisites:
# - Azure CLI installed (az)
# - Azure CLI logged in (az login)
# - Contributor access to Azure subscription
#==============================================================================

set -e

# Configuration
LOCATION="${1:-eastus2}"
RESOURCE_GROUP="rg-terraform-state"
STORAGE_ACCOUNT_PREFIX="sttfstatefinrisk"
CONTAINER_NAME="tfstate"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Terraform State Bootstrap${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI is not installed.${NC}"
    echo "Please install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    echo -e "${RED}Error: Not logged in to Azure.${NC}"
    echo "Please run: az login"
    exit 1
fi

# Get subscription info
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)

echo -e "${YELLOW}Subscription:${NC} $SUBSCRIPTION_NAME"
echo -e "${YELLOW}Subscription ID:${NC} $SUBSCRIPTION_ID"
echo -e "${YELLOW}Location:${NC} $LOCATION"
echo ""

# Generate unique storage account name (must be 3-24 chars, alphanumeric only)
RANDOM_SUFFIX=$(openssl rand -hex 3)
STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_PREFIX}${RANDOM_SUFFIX}"

# Ensure storage account name is valid (max 24 chars)
if [ ${#STORAGE_ACCOUNT_NAME} -gt 24 ]; then
    STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_PREFIX}${RANDOM_SUFFIX:0:4}"
fi

echo -e "${YELLOW}Storage Account:${NC} $STORAGE_ACCOUNT_NAME"
echo ""

#------------------------------------------------------------------------------
# Create Resource Group
#------------------------------------------------------------------------------
echo -e "${GREEN}Creating resource group...${NC}"

if az group show --name $RESOURCE_GROUP &> /dev/null; then
    echo -e "${YELLOW}Resource group '$RESOURCE_GROUP' already exists.${NC}"
else
    az group create \
        --name $RESOURCE_GROUP \
        --location $LOCATION \
        --tags Purpose="Terraform State" ManagedBy="Bootstrap Script"

    echo -e "${GREEN}✓ Resource group created: $RESOURCE_GROUP${NC}"
fi

#------------------------------------------------------------------------------
# Create Storage Account
#------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}Creating storage account...${NC}"

if az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP &> /dev/null; then
    echo -e "${YELLOW}Storage account '$STORAGE_ACCOUNT_NAME' already exists.${NC}"
else
    az storage account create \
        --name $STORAGE_ACCOUNT_NAME \
        --resource-group $RESOURCE_GROUP \
        --location $LOCATION \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --allow-blob-public-access false \
        --min-tls-version TLS1_2 \
        --https-only true

    echo -e "${GREEN}✓ Storage account created: $STORAGE_ACCOUNT_NAME${NC}"
fi

#------------------------------------------------------------------------------
# Create Blob Container
#------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}Creating blob container...${NC}"

# Get storage account key
STORAGE_KEY=$(az storage account keys list \
    --resource-group $RESOURCE_GROUP \
    --account-name $STORAGE_ACCOUNT_NAME \
    --query '[0].value' \
    --output tsv)

# Check if container exists
if az storage container show --name $CONTAINER_NAME --account-name $STORAGE_ACCOUNT_NAME --account-key $STORAGE_KEY &> /dev/null; then
    echo -e "${YELLOW}Container '$CONTAINER_NAME' already exists.${NC}"
else
    az storage container create \
        --name $CONTAINER_NAME \
        --account-name $STORAGE_ACCOUNT_NAME \
        --account-key $STORAGE_KEY

    echo -e "${GREEN}✓ Container created: $CONTAINER_NAME${NC}"
fi

#------------------------------------------------------------------------------
# Output Configuration
#------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Bootstrap Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Terraform Backend Configuration:${NC}"
echo ""
echo "Copy this to your backend.hcl files:"
echo ""
echo -e "${GREEN}# Dev environment: terraform/environments/dev/backend.hcl${NC}"
cat << EOF
resource_group_name  = "$RESOURCE_GROUP"
storage_account_name = "$STORAGE_ACCOUNT_NAME"
container_name       = "$CONTAINER_NAME"
key                  = "finrisk-dev.tfstate"
EOF

echo ""
echo -e "${GREEN}# Prod environment: terraform/environments/prod/backend.hcl${NC}"
cat << EOF
resource_group_name  = "$RESOURCE_GROUP"
storage_account_name = "$STORAGE_ACCOUNT_NAME"
container_name       = "$CONTAINER_NAME"
key                  = "finrisk-prod.tfstate"
EOF

echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Copy backend.hcl.example to backend.hcl in each environment"
echo "2. Update backend.hcl with the values above"
echo "3. Run: terraform init -backend-config=backend.hcl"
echo ""
echo -e "${YELLOW}Storage Account Key (for CI/CD):${NC}"
echo "Set this as a secret variable in Azure DevOps:"
echo "  Variable: ARM_ACCESS_KEY"
echo "  Value: ${STORAGE_KEY:0:20}..." # Show partial key for verification
echo ""
echo -e "${RED}IMPORTANT: Store the storage account key securely!${NC}"
echo "You can retrieve it later with:"
echo "  az storage account keys list --account-name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP --query '[0].value' -o tsv"
