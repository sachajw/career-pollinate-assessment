#!/bin/bash
set -euo pipefail

#------------------------------------------------------------------------------
# Custom Certificate Setup Script for Azure Container Apps
#------------------------------------------------------------------------------
# This script helps configure a custom domain with SSL certificate.
#
# Usage:
#   ./scripts/setup-custom-certificate.sh --cert /path/to/cert.pem --domain api.example.com
#
# Prerequisites:
#   - openssl (for certificate conversion)
#   - Azure CLI (for verification)
#   - Terraform (for deployment)
#------------------------------------------------------------------------------

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
CERT_FILE=""
DOMAIN_NAME=""
CERT_PASSWORD=""
OUTPUT_DIR="./terraform/environments/dev"
SKIP_APPLY=false

#------------------------------------------------------------------------------
# Functions
#------------------------------------------------------------------------------

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Configure custom domain and SSL certificate for Azure Container App.

OPTIONS:
    -c, --cert FILE         Path to certificate file (PEM or PFX)
    -d, --domain NAME       Custom domain name (e.g., api.pangarabbit.com)
    -p, --password PASS     Certificate password (if PFX is encrypted)
    -o, --output-dir DIR    Terraform environment directory (default: ./terraform/environments/dev)
    --skip-apply            Skip Terraform apply (just prepare files)
    -h, --help              Show this help message

EXAMPLES:
    # Setup with PEM certificate
    $0 --cert /path/to/cloudflare-cert.pem --domain api.pangarabbit.com

    # Setup with password-protected PFX
    $0 --cert /path/to/cert.pfx --domain api.example.com --password "MyPassword123"

    # Prepare files only (no Terraform apply)
    $0 --cert cert.pem --domain api.example.com --skip-apply

EOF
}

#------------------------------------------------------------------------------
# Parse Arguments
#------------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--cert)
            CERT_FILE="$2"
            shift 2
            ;;
        -d|--domain)
            DOMAIN_NAME="$2"
            shift 2
            ;;
        -p|--password)
            CERT_PASSWORD="$2"
            shift 2
            ;;
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --skip-apply)
            SKIP_APPLY=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

#------------------------------------------------------------------------------
# Validation
#------------------------------------------------------------------------------

print_header "Certificate Setup Validation"

if [[ -z "$CERT_FILE" ]]; then
    print_error "Certificate file is required"
    show_usage
    exit 1
fi

if [[ ! -f "$CERT_FILE" ]]; then
    print_error "Certificate file not found: $CERT_FILE"
    exit 1
fi

if [[ -z "$DOMAIN_NAME" ]]; then
    print_error "Domain name is required"
    show_usage
    exit 1
fi

print_success "Certificate file: $CERT_FILE"
print_success "Domain name: $DOMAIN_NAME"

#------------------------------------------------------------------------------
# Detect Certificate Format
#------------------------------------------------------------------------------

print_header "Certificate Format Detection"

CERT_FORMAT=""
if openssl x509 -in "$CERT_FILE" -noout 2>/dev/null; then
    CERT_FORMAT="PEM"
    print_info "Detected PEM format"
elif openssl pkcs12 -in "$CERT_FILE" -noout -password pass: 2>/dev/null; then
    CERT_FORMAT="PFX"
    print_info "Detected PFX format (no password)"
elif openssl pkcs12 -in "$CERT_FILE" -noout -password pass:"$CERT_PASSWORD" 2>/dev/null; then
    CERT_FORMAT="PFX_ENCRYPTED"
    print_info "Detected PFX format (encrypted)"
else
    print_error "Unable to detect certificate format"
    print_info "Ensure it's a valid PEM or PFX file"
    exit 1
fi

#------------------------------------------------------------------------------
# Convert to PFX if needed
#------------------------------------------------------------------------------

print_header "Certificate Conversion"

PFX_FILE=""
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

if [[ "$CERT_FORMAT" == "PEM" ]]; then
    print_info "Converting PEM to PFX..."
    PFX_FILE="$TEMP_DIR/converted.pfx"

    if [[ -n "$CERT_PASSWORD" ]]; then
        openssl pkcs12 -export -out "$PFX_FILE" \
            -inkey "$CERT_FILE" -in "$CERT_FILE" \
            -passout pass:"$CERT_PASSWORD"
    else
        openssl pkcs12 -export -out "$PFX_FILE" \
            -inkey "$CERT_FILE" -in "$CERT_FILE" \
            -passout pass:
    fi

    print_success "Converted to PFX format"
else
    PFX_FILE="$CERT_FILE"
    print_success "Already in PFX format"
fi

#------------------------------------------------------------------------------
# Base64 Encode
#------------------------------------------------------------------------------

print_header "Certificate Encoding"

print_info "Encoding certificate to base64..."
CERT_BASE64=$(base64 -i "$PFX_FILE")
print_success "Certificate encoded successfully"

#------------------------------------------------------------------------------
# Extract Certificate Info
#------------------------------------------------------------------------------

print_header "Certificate Information"

if [[ -n "$CERT_PASSWORD" ]]; then
    CERT_INFO=$(openssl pkcs12 -in "$PFX_FILE" -noout -info -password pass:"$CERT_PASSWORD" 2>&1 || echo "")
else
    CERT_INFO=$(openssl pkcs12 -in "$PFX_FILE" -noout -info -password pass: 2>&1 || echo "")
fi

# Try to get certificate details
if [[ -n "$CERT_PASSWORD" ]]; then
    openssl pkcs12 -in "$PFX_FILE" -nokeys -password pass:"$CERT_PASSWORD" 2>/dev/null | openssl x509 -noout -subject -dates || true
else
    openssl pkcs12 -in "$PFX_FILE" -nokeys -password pass: 2>/dev/null | openssl x509 -noout -subject -dates || true
fi

#------------------------------------------------------------------------------
# Generate Terraform Configuration
#------------------------------------------------------------------------------

print_header "Terraform Configuration"

# Generate certificate name from domain
CERT_NAME=$(echo "$DOMAIN_NAME" | sed 's/\./-/g')-cert

print_info "Generating Terraform variables..."

# Create terraform.tfvars snippet
TFVARS_FILE="$TEMP_DIR/certificate.auto.tfvars"
cat > "$TFVARS_FILE" << EOF
# Custom Domain and Certificate Configuration
# Generated by setup-custom-certificate.sh on $(date)

custom_domain_enabled = true
custom_domain_name    = "$DOMAIN_NAME"
certificate_name      = "$CERT_NAME"
certificate_password  = "$CERT_PASSWORD"

# SECURITY WARNING: This file contains sensitive certificate data.
# Do NOT commit this file to version control!
# Consider using environment variables instead.

certificate_blob_base64 = <<-EOT
$CERT_BASE64
EOT
EOF

print_success "Terraform variables generated"

#------------------------------------------------------------------------------
# Display Instructions
#------------------------------------------------------------------------------

print_header "Next Steps"

cat << EOF

${GREEN}✓ Certificate prepared successfully!${NC}

${YELLOW}IMPORTANT SECURITY NOTES:${NC}
1. The certificate has been encoded and is ready to use
2. ${RED}DO NOT commit certificate files to Git${NC}
3. Add *.pfx, *.pfx.b64, *.pem to .gitignore
4. For production, use Azure Key Vault to store certificates

${BLUE}DNS Configuration Required:${NC}
After deploying, configure these DNS records:

For subdomain ($DOMAIN_NAME):
  Type: CNAME
  Name: ${DOMAIN_NAME%%.*}
  Value: <container_app_fqdn>  (get from: terraform output application_url)

  Type: TXT
  Name: asuid.${DOMAIN_NAME%%.*}
  Value: <verification_id>  (get from: terraform output custom_domain_verification_id)

${BLUE}Option 1: Apply via Terraform (recommended for production)${NC}

cd $OUTPUT_DIR
terraform init -backend-config=backend.hcl
terraform plan -var-file="$TFVARS_FILE" -out=tfplan
terraform apply tfplan

${BLUE}Option 2: Use Environment Variables (more secure)${NC}

export TF_VAR_custom_domain_enabled=true
export TF_VAR_custom_domain_name="$DOMAIN_NAME"
export TF_VAR_certificate_name="$CERT_NAME"
export TF_VAR_certificate_password="$CERT_PASSWORD"
export TF_VAR_certificate_blob_base64=\$(cat $TEMP_DIR/cert.b64)

cd $OUTPUT_DIR
terraform plan -out=tfplan
terraform apply tfplan

${BLUE}Verification:${NC}

# After deployment, test the custom domain
curl -I https://$DOMAIN_NAME/health

# Check certificate
openssl s_client -connect $DOMAIN_NAME:443 -servername $DOMAIN_NAME < /dev/null

${BLUE}Files Generated:${NC}
- Terraform variables: $TFVARS_FILE

EOF

# Copy tfvars file if not skipping
if [[ "$SKIP_APPLY" == false ]]; then
    cp "$TFVARS_FILE" "$OUTPUT_DIR/certificate.auto.tfvars"
    print_warning "Certificate variables copied to: $OUTPUT_DIR/certificate.auto.tfvars"
    print_warning "Remember to add this file to .gitignore!"

    # Add to .gitignore
    if ! grep -q "certificate.auto.tfvars" "$OUTPUT_DIR/.gitignore" 2>/dev/null; then
        echo "certificate.auto.tfvars" >> "$OUTPUT_DIR/.gitignore"
        print_success "Added certificate.auto.tfvars to .gitignore"
    fi
fi

print_success "Setup complete!"
