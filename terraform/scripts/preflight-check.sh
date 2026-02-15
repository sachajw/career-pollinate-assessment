#!/bin/bash
#------------------------------------------------------------------------------
# Terraform Pre-flight Check Script
#------------------------------------------------------------------------------
# Validates prerequisites before Terraform deployment:
# - Azure CLI authentication
# - Required Azure resource providers
# - Terraform installation
# - Subscription permissions
#
# Usage:
#   ./preflight-check.sh
#
# Exit codes:
#   0 - All checks passed
#   1 - One or more checks failed
#------------------------------------------------------------------------------

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track overall status
CHECKS_PASSED=0
CHECKS_FAILED=0

# Header
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                                                                              ║"
echo "║                    Terraform Pre-flight Checks                               ║"
echo "║                    FinRisk Platform - Development                            ║"
echo "║                                                                              ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

#------------------------------------------------------------------------------
# Check 1: Azure CLI Installation
#------------------------------------------------------------------------------
echo -n "Checking Azure CLI installation... "
if command -v az &> /dev/null; then
  AZ_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
  echo -e "${GREEN}✅ Installed${NC} (version: $AZ_VERSION)"
  ((CHECKS_PASSED++))
else
  echo -e "${RED}❌ Not found${NC}"
  echo "   Install: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
  ((CHECKS_FAILED++))
  exit 1
fi

#------------------------------------------------------------------------------
# Check 2: Azure CLI Authentication
#------------------------------------------------------------------------------
echo -n "Checking Azure CLI authentication... "
if az account show &>/dev/null; then
  ACCOUNT_NAME=$(az account show --query name -o tsv)
  SUBSCRIPTION_ID=$(az account show --query id -o tsv)
  echo -e "${GREEN}✅ Authenticated${NC}"
  echo "   Account: $ACCOUNT_NAME"
  echo "   Subscription: $SUBSCRIPTION_ID"
  ((CHECKS_PASSED++))
else
  echo -e "${RED}❌ Not authenticated${NC}"
  echo "   Run: az login"
  ((CHECKS_FAILED++))
  exit 1
fi

#------------------------------------------------------------------------------
# Check 3: Terraform Installation
#------------------------------------------------------------------------------
echo -n "Checking Terraform installation... "
if command -v terraform &> /dev/null; then
  TF_VERSION=$(terraform version -json 2>/dev/null | grep -o '"terraform_version":"[^"]*' | cut -d'"' -f4)
  echo -e "${GREEN}✅ Installed${NC} (version: $TF_VERSION)"

  # Check minimum version (1.5.0)
  REQUIRED_VERSION="1.5.0"
  if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$TF_VERSION" | sort -V | head -n1)" = "$REQUIRED_VERSION" ]; then
    echo "   Version requirement met (>= $REQUIRED_VERSION)"
    ((CHECKS_PASSED++))
  else
    echo -e "   ${YELLOW}⚠️  Warning: Version $TF_VERSION < $REQUIRED_VERSION${NC}"
    echo "   Recommended: Upgrade to Terraform $REQUIRED_VERSION+"
  fi
else
  echo -e "${RED}❌ Not found${NC}"
  echo "   Install: https://www.terraform.io/downloads"
  ((CHECKS_FAILED++))
  exit 1
fi

#------------------------------------------------------------------------------
# Check 4: Azure Resource Providers
#------------------------------------------------------------------------------
echo ""
echo "Checking Azure resource providers..."

PROVIDERS=(
  "Microsoft.App"
  "Microsoft.ContainerRegistry"
  "Microsoft.KeyVault"
  "Microsoft.OperationalInsights"
  "Microsoft.Insights"
  "Microsoft.Storage"
)

PROVIDERS_TO_REGISTER=()

for PROVIDER in "${PROVIDERS[@]}"; do
  echo -n "  • $PROVIDER... "

  STATE=$(az provider show --namespace "$PROVIDER" --query registrationState -o tsv 2>/dev/null || echo "Unknown")

  if [ "$STATE" = "Registered" ]; then
    echo -e "${GREEN}✅ Registered${NC}"
    ((CHECKS_PASSED++))
  elif [ "$STATE" = "Registering" ]; then
    echo -e "${YELLOW}⏳ Registering (in progress)${NC}"
    PROVIDERS_TO_REGISTER+=("$PROVIDER")
  else
    echo -e "${YELLOW}⚠️  Not registered${NC}"
    PROVIDERS_TO_REGISTER+=("$PROVIDER")
  fi
done

#------------------------------------------------------------------------------
# Auto-register providers if needed
#------------------------------------------------------------------------------
if [ ${#PROVIDERS_TO_REGISTER[@]} -gt 0 ]; then
  echo ""
  echo -e "${BLUE}ℹ️  Registering ${#PROVIDERS_TO_REGISTER[@]} provider(s)...${NC}"
  echo ""

  for PROVIDER in "${PROVIDERS_TO_REGISTER[@]}"; do
    echo "  Registering $PROVIDER..."
    az provider register --namespace "$PROVIDER" --wait 2>&1 | grep -v "Registering" || true
    echo -e "  ${GREEN}✅ $PROVIDER registered${NC}"
  done

  echo ""
  echo -e "${GREEN}✅ All providers registered successfully${NC}"
fi

#------------------------------------------------------------------------------
# Check 5: Subscription Permissions
#------------------------------------------------------------------------------
echo ""
echo -n "Checking subscription permissions... "

# Check if user has Contributor or Owner role
ROLE=$(az role assignment list --assignee $(az account show --query user.name -o tsv) --query "[?roleDefinitionName=='Owner' || roleDefinitionName=='Contributor'].roleDefinitionName | [0]" -o tsv 2>/dev/null || echo "")

if [ "$ROLE" = "Owner" ] || [ "$ROLE" = "Contributor" ]; then
  echo -e "${GREEN}✅ Sufficient (Role: $ROLE)${NC}"
  ((CHECKS_PASSED++))
elif [ -n "$ROLE" ]; then
  echo -e "${YELLOW}⚠️  Limited (Role: $ROLE)${NC}"
  echo "   Note: May not have permissions to create all resources"
  echo "   Required: Contributor or Owner role"
else
  echo -e "${YELLOW}⚠️  Unable to verify${NC}"
  echo "   Ensure you have Contributor or Owner role on the subscription"
fi

#------------------------------------------------------------------------------
# Check 6: Docker Installation (Optional)
#------------------------------------------------------------------------------
echo -n "Checking Docker installation... "
if command -v docker &> /dev/null; then
  DOCKER_VERSION=$(docker --version | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -n1)
  echo -e "${GREEN}✅ Installed${NC} (version: $DOCKER_VERSION)"

  # Check if Docker is running
  if docker ps &>/dev/null; then
    echo "   Docker daemon is running"
  else
    echo -e "   ${YELLOW}⚠️  Docker daemon is not running${NC}"
    echo "   Start Docker Desktop or Docker service"
  fi
else
  echo -e "${YELLOW}⚠️  Not found (optional)${NC}"
  echo "   Required for: Building and pushing container images"
  echo "   Install: https://docs.docker.com/get-docker/"
fi

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
  echo -e "${GREEN}✅ All pre-flight checks passed!${NC}"
  echo ""
  echo "You can now proceed with deployment:"
  echo "  cd terraform/environments/dev"
  echo "  terraform init -backend-config=backend.hcl"
  echo "  terraform plan"
  echo "  terraform apply"
  echo ""
  exit 0
else
  echo -e "${RED}❌ $CHECKS_FAILED check(s) failed${NC}"
  echo ""
  echo "Please resolve the issues above before running Terraform."
  echo ""
  exit 1
fi
