#!/bin/bash
#------------------------------------------------------------------------------
# Terraform with Environment Variables
#------------------------------------------------------------------------------
# Loads .env file and runs terraform commands
#
# Usage:
#   ./run.sh init
#   ./run.sh plan
#   ./run.sh apply
#------------------------------------------------------------------------------

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env file
ENV_FILE="${SCRIPT_DIR}/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Error: .env file not found at $ENV_FILE${NC}"
    echo "Copy .env.example to .env and fill in your values:"
    echo "  cp .env.example .env"
    exit 1
fi

# Load environment variables
echo -e "${GREEN}Loading environment from .env...${NC}"
set -a
source "$ENV_FILE"
set +a

# Validate required variables
REQUIRED_VARS=(
    "AZDO_ORG_SERVICE_URL"
    "AZDO_PERSONAL_ACCESS_TOKEN"
    "AZDO_PROJECT_ID"
    "ARM_CLIENT_ID"
    "ARM_CLIENT_SECRET"
    "ARM_TENANT_ID"
    "ARM_SUBSCRIPTION_ID"
)

MISSING_VARS=()
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ] || [[ "${!var}" == "your-"* ]]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo -e "${RED}Error: Missing or unset environment variables:${NC}"
    for var in "${MISSING_VARS[@]}"; do
        echo "  - $var"
    done
    echo ""
    echo "Edit $ENV_FILE and set the required values."
    exit 1
fi

echo -e "${GREEN}✅ All required variables are set${NC}"
echo ""

# Export for Terraform
export AZDO_ORG_SERVICE_URL
export AZDO_PERSONAL_ACCESS_TOKEN
export AZDO_PROJECT_ID
export ARM_CLIENT_ID
export ARM_CLIENT_SECRET
export ARM_TENANT_ID
export ARM_SUBSCRIPTION_ID
export GITHUB_REPOSITORY_URL

# Run terraform command
cd "$SCRIPT_DIR"

case "${1:-}" in
    init)
        echo -e "${YELLOW}Running terraform init...${NC}"
        terraform init -backend-config=backend.hcl
        ;;
    plan)
        echo -e "${YELLOW}Running terraform plan...${NC}"
        terraform plan -out=tfplan
        ;;
    apply)
        echo -e "${YELLOW}Running terraform apply...${NC}"
        terraform apply tfplan
        ;;
    destroy)
        echo -e "${RED}Running terraform destroy...${NC}"
        terraform destroy
        ;;
    *)
        echo "Usage: $0 {init|plan|apply|destroy}"
        exit 1
        ;;
esac
