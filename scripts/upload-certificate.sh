#!/bin/bash
set -euo pipefail

#------------------------------------------------------------------------------
# One-Time Certificate Upload for Azure Container App Environment
#------------------------------------------------------------------------------
# This script uploads your Cloudflare certificate to the Container App Environment.
# Run this ONCE after the Container App Environment is created.
#
# Usage:
#   ./scripts/upload-certificate.sh
#
# Prerequisites:
#   - Azure CLI installed and authenticated (az login)
#   - Container App Environment already created (via Terraform)
#   - Certificate file at: /Users/tvl/Desktop/cloudflare-cert.pfx
#------------------------------------------------------------------------------

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
CERT_FILE="/Users/tvl/Desktop/cloudflare-cert.pfx"
CERT_NAME="finrisk-pangarabbit-cert"
RESOURCE_GROUP="rg-finrisk-dev"
ENVIRONMENT_NAME="cae-finrisk-dev"
DOMAIN_NAME="finrisk.pangarabbit.com"

echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}        Certificate Upload - finrisk.pangarabbit.com            ${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}✗ Azure CLI not found. Install from: https://aka.ms/azure-cli${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Azure CLI found${NC}"

# Check if logged in
if ! az account show &> /dev/null; then
    echo -e "${YELLOW}⚠ Not logged into Azure. Running 'az login'...${NC}"
    az login
fi
echo -e "${GREEN}✓ Azure authentication verified${NC}"

# Check if certificate file exists
if [[ ! -f "$CERT_FILE" ]]; then
    echo -e "${RED}✗ Certificate not found: $CERT_FILE${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Certificate file found${NC}"

# Check if Container App Environment exists
echo -e "${BLUE}Checking Container App Environment...${NC}"
if ! az containerapp env show \
    --name "$ENVIRONMENT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    &> /dev/null; then
    echo -e "${RED}✗ Container App Environment not found: $ENVIRONMENT_NAME${NC}"
    echo -e "${YELLOW}Run Terraform first to create the environment:${NC}"
    echo -e "  cd terraform/environments/dev"
    echo -e "  terraform apply"
    exit 1
fi
echo -e "${GREEN}✓ Container App Environment exists${NC}"

# Check if certificate already exists
echo -e "${BLUE}Checking for existing certificate...${NC}"
if az containerapp env certificate list \
    --name "$ENVIRONMENT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?name=='$CERT_NAME'].name" -o tsv | grep -q "$CERT_NAME"; then
    echo -e "${YELLOW}⚠ Certificate '$CERT_NAME' already exists${NC}"
    read -p "Do you want to delete and re-upload? (yes/no): " confirm
    if [[ "$confirm" == "yes" ]]; then
        echo -e "${BLUE}Deleting existing certificate...${NC}"
        az containerapp env certificate delete \
            --name "$ENVIRONMENT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --certificate "$CERT_NAME" \
            --yes
        echo -e "${GREEN}✓ Existing certificate deleted${NC}"
    else
        echo -e "${YELLOW}Using existing certificate${NC}"
        exit 0
    fi
fi

# Upload certificate
echo -e "${BLUE}Uploading certificate...${NC}"
az containerapp env certificate upload \
    --name "$ENVIRONMENT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --certificate-file "$CERT_FILE" \
    --certificate-name "$CERT_NAME" \
    --password ""

echo -e "${GREEN}✓ Certificate uploaded successfully${NC}"
echo ""

# List certificates
echo -e "${BLUE}Certificates in environment:${NC}"
az containerapp env certificate list \
    --name "$ENVIRONMENT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "[].{Name:name, Subject:properties.subjectName, Thumbprint:properties.thumbprint, ExpirationDate:properties.expirationDate}" \
    --output table

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                 Certificate Upload Complete!                   ${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo ""
echo -e "1. Deploy infrastructure with Terraform:"
echo -e "   ${YELLOW}cd terraform/environments/dev${NC}"
echo -e "   ${YELLOW}terraform plan -out=tfplan${NC}"
echo -e "   ${YELLOW}terraform apply tfplan${NC}"
echo ""
echo -e "2. Get the Container App FQDN:"
echo -e "   ${YELLOW}terraform output application_url${NC}"
echo -e "   ${YELLOW}terraform output custom_domain_verification_id${NC}"
echo ""
echo -e "3. Configure DNS in Cloudflare:"
echo -e "   ${BLUE}CNAME Record:${NC}"
echo -e "     Type:   CNAME"
echo -e "     Name:   finrisk"
echo -e "     Target: <container_app_fqdn>"
echo -e "     Proxy:  ✅ Enabled"
echo ""
echo -e "   ${BLUE}TXT Record:${NC}"
echo -e "     Type:    TXT"
echo -e "     Name:    asuid.finrisk"
echo -e "     Content: <verification_id>"
echo -e "     Proxy:   ⬜ DNS only"
echo ""
echo -e "4. Set Cloudflare SSL/TLS mode to: ${BLUE}Full (strict)${NC}"
echo ""
echo -e "5. Test: ${YELLOW}curl -I https://$DOMAIN_NAME/health${NC}"
echo ""
