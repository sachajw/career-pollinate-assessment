#!/bin/bash
set -euo pipefail

#------------------------------------------------------------------------------
# Deploy with Custom Domain - Development Environment
#------------------------------------------------------------------------------
# Deploys the Container App with custom domain enabled.
#
# Usage: ./deploy-with-certificate.sh
#
# Prerequisites:
#   - Certificate already uploaded (run upload-certificate.sh first)
#   - Terraform initialized
#------------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$TERRAFORM_ROOT/../environments/dev"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}        FinRisk Platform - Development Deployment              ${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

# Change to Terraform directory
cd "$TERRAFORM_DIR"

echo -e "${BLUE}Terraform Directory: ${NC}$TERRAFORM_DIR"
echo ""

# Initialize if needed
if [[ ! -d ".terraform" ]]; then
    echo -e "${BLUE}Initializing Terraform...${NC}"
    terraform init -backend-config=backend.hcl
    echo ""
fi

# Plan
echo -e "${BLUE}Planning deployment...${NC}"
terraform plan -out=tfplan
echo ""

# Ask for confirmation
read -p "Apply this plan? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo -e "${YELLOW}Deployment cancelled${NC}"
    exit 0
fi

# Apply
echo -e "${BLUE}Applying changes...${NC}"
terraform apply tfplan
echo ""

# Get outputs
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                 Deployment Complete!                          ${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""

APPLICATION_URL=$(terraform output -raw application_url 2>/dev/null || echo "N/A")
VERIFICATION_ID=$(terraform output -raw custom_domain_verification_id 2>/dev/null || echo "N/A")

echo -e "${BLUE}Application URL:${NC} $APPLICATION_URL"
echo -e "${BLUE}Domain Verification ID:${NC} $VERIFICATION_ID"
echo ""

echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}               DNS Configuration Required                       ${NC}"
echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Configure these DNS records in Cloudflare:"
echo ""
echo -e "${BLUE}Record 1 - CNAME for finrisk subdomain:${NC}"
echo "  Type:   CNAME"
echo "  Name:   finrisk"
echo "  Target: ${APPLICATION_URL#https://}"
echo "  Proxy:  Enabled (orange cloud)"
echo ""
echo -e "${BLUE}Record 2 - TXT for domain verification:${NC}"
echo "  Type:    TXT"
echo "  Name:    asuid.finrisk"
echo "  Content: $VERIFICATION_ID"
echo "  Proxy:   DNS only (gray cloud)"
echo ""
echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}            Cloudflare SSL Configuration                        ${NC}"
echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "1. Go to SSL/TLS -> Overview"
echo "2. Set mode to: ${BLUE}Full (strict)${NC}"
echo "3. Verify Origin Server certificate is active"
echo ""
echo -e "${GREEN}After DNS propagates (5-10 minutes), test with:${NC}"
echo "  curl -I https://finrisk.pangarabbit.com/health"
echo ""
