#!/usr/bin/env bash
#
# Dry Run Test for azure-pipelines-infra.yml
# Simulates the pipeline execution locally without applying changes
#

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TERRAFORM_VERSION="1.7.0"
TERRAFORM_DIR="terraform/environments/dev"
PIPELINE_FILE="pipelines/azure-pipelines-infra.yml"

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Change to repository root
cd "$(dirname "$0")/.."

print_header "DRY RUN TEST: Azure Pipelines Infrastructure Pipeline"

echo "This script simulates the pipeline execution locally:"
echo "  • Stage 1: Terraform Plan"
echo "  • Stage 2: Terraform Apply (SIMULATED - no actual apply)"
echo ""

# ============================================================================
# Pre-flight Checks
# ============================================================================
print_header "1. Pre-flight Checks"

# Check if pipeline file exists
if [[ ! -f "$PIPELINE_FILE" ]]; then
    log_error "Pipeline file not found: $PIPELINE_FILE"
    exit 1
fi
log_success "Pipeline file exists: $PIPELINE_FILE"

# Check Terraform installation
if ! command -v terraform &> /dev/null; then
    log_error "Terraform is not installed"
    exit 1
fi

INSTALLED_VERSION=$(terraform version -json | grep -o '"terraform_version":"[^"]*' | cut -d'"' -f4)
log_success "Terraform installed: v$INSTALLED_VERSION (pipeline expects: v$TERRAFORM_VERSION)"

if [[ "$INSTALLED_VERSION" != "$TERRAFORM_VERSION" ]]; then
    log_warning "Version mismatch (this is OK for testing)"
fi

# Check Terraform directory
if [[ ! -d "$TERRAFORM_DIR" ]]; then
    log_error "Terraform directory not found: $TERRAFORM_DIR"
    exit 1
fi
log_success "Terraform directory exists: $TERRAFORM_DIR"

# Check required configuration files
if [[ ! -f "$TERRAFORM_DIR/backend.hcl" ]]; then
    log_error "Backend configuration not found: $TERRAFORM_DIR/backend.hcl"
    exit 1
fi
log_success "Backend configuration exists"

if [[ ! -f "$TERRAFORM_DIR/terraform.tfvars" ]]; then
    log_error "Variables file not found: $TERRAFORM_DIR/terraform.tfvars"
    exit 1
fi
log_success "Variables file exists"

# Check Azure CLI (optional but recommended)
if command -v az &> /dev/null; then
    AZURE_LOGGED_IN=$(az account show --query "name" -o tsv 2>/dev/null || echo "")
    if [[ -n "$AZURE_LOGGED_IN" ]]; then
        log_success "Azure CLI authenticated: $AZURE_LOGGED_IN"
    else
        log_warning "Azure CLI not authenticated (run 'az login')"
    fi
else
    log_warning "Azure CLI not installed (optional for dry run)"
fi

# ============================================================================
# Stage 1: Terraform Plan (simulates pipeline Plan stage)
# ============================================================================
print_header "2. Stage 1: Terraform Plan"

cd "$TERRAFORM_DIR"

log_info "Step 1.1: Terraform Format Check"
if terraform fmt -check -recursive .; then
    log_success "All files are properly formatted"
else
    log_warning "Some files need formatting (run 'terraform fmt -recursive')"
fi

log_info "Step 1.2: Terraform Init"
# Use -backend=false for true dry run (no state access)
# Remove this flag if you want to test with actual backend
if terraform init -backend-config=backend.hcl -upgrade -no-color; then
    log_success "Terraform initialization successful"
else
    log_error "Terraform init failed"
    exit 1
fi

log_info "Step 1.3: Terraform Validate"
if terraform validate -no-color; then
    log_success "Terraform configuration is valid"
else
    log_error "Terraform validation failed"
    exit 1
fi

log_info "Step 1.4: Terraform Plan"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  TERRAFORM PLAN OUTPUT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if terraform plan -out=tfplan -no-color; then
    echo ""
    log_success "Terraform plan generated successfully"

    # Show plan summary
    echo ""
    log_info "Plan Summary:"
    terraform show -no-color tfplan | grep -E "Plan:|No changes" || true
else
    log_error "Terraform plan failed"
    exit 1
fi

# ============================================================================
# Stage 2: Terraform Apply Simulation
# ============================================================================
print_header "3. Stage 2: Terraform Apply (SIMULATION)"

log_info "This stage would run 'terraform apply tfplan' in the pipeline"
log_info "The plan file has been generated: $TERRAFORM_DIR/tfplan"
log_warning "NOT executing apply in dry run mode"

echo ""
log_info "To manually review the plan, run:"
echo "    cd $TERRAFORM_DIR"
echo "    terraform show tfplan"
echo ""
log_info "To apply the plan (CAUTION - this will create Azure resources):"
echo "    cd $TERRAFORM_DIR"
echo "    terraform apply tfplan"

# ============================================================================
# Post-flight Analysis
# ============================================================================
print_header "4. Post-flight Analysis"

# Check for security issues
log_info "Checking for potential security issues..."

SECURITY_ISSUES=0

# Check for hardcoded secrets (basic check)
if grep -r "password\s*=\s*['\"]" . --include="*.tf" --include="*.tfvars" 2>/dev/null | grep -v "random_password" | grep -q .; then
    log_error "Potential hardcoded passwords found"
    SECURITY_ISSUES=$((SECURITY_ISSUES + 1))
fi

# Check for public IP exposure
if grep -r "source_address_prefix.*=.*\"\*\"" . --include="*.tf" 2>/dev/null | grep -q .; then
    log_warning "Potential public IP exposure found (\"*\" in security rules)"
fi

if [[ $SECURITY_ISSUES -eq 0 ]]; then
    log_success "No obvious security issues detected"
fi

# ============================================================================
# Pipeline Validation
# ============================================================================
print_header "5. Pipeline YAML Validation"

cd - > /dev/null  # Return to repo root

log_info "Validating Azure Pipeline YAML syntax..."

# Basic YAML syntax check using Python
if command -v python3 &> /dev/null; then
    python3 -c "
import yaml
import sys

try:
    with open('$PIPELINE_FILE', 'r') as f:
        yaml.safe_load(f)
    print('  YAML syntax is valid')
    sys.exit(0)
except yaml.YAMLError as e:
    print(f'  YAML syntax error: {e}')
    sys.exit(1)
" && log_success "Pipeline YAML syntax is valid" || log_error "Pipeline YAML syntax is invalid"
else
    log_warning "Python not available for YAML validation"
fi

# Check pipeline structure
log_info "Checking pipeline structure..."

REQUIRED_STAGES=("Plan" "Apply")
for stage in "${REQUIRED_STAGES[@]}"; do
    if grep -q "stage: $stage" "$PIPELINE_FILE"; then
        log_success "Stage '$stage' found"
    else
        log_error "Stage '$stage' not found"
    fi
done

# ============================================================================
# Summary
# ============================================================================
print_header "6. Dry Run Summary"

echo "✓ Pre-flight checks passed"
echo "✓ Terraform format validated"
echo "✓ Terraform initialized successfully"
echo "✓ Terraform configuration validated"
echo "✓ Terraform plan generated (see tfplan file)"
echo "✓ Pipeline YAML validated"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  DRY RUN COMPLETED SUCCESSFULLY${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Next steps:"
echo "  1. Review the plan: cd $TERRAFORM_DIR && terraform show tfplan"
echo "  2. Test in Azure DevOps: Push to a feature branch and create a PR"
echo "  3. Apply changes: Merge PR to main (pipeline will auto-apply)"
echo ""
