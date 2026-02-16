#!/usr/bin/env bash
#
# Terraform Test Runner
# Runs Terratest suite for infrastructure modules
#

set -e
set -u

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Run Terratest infrastructure tests

OPTIONS:
    -a, --all           Run all tests (default)
    -s, --short         Run only short/fast tests (validation only)
    -m, --module NAME   Run tests for specific module
    -v, --verbose       Enable verbose output
    -p, --parallel N    Run N tests in parallel (default: 4)
    -t, --timeout MIN   Set timeout in minutes (default: 60)
    -h, --help          Show this help message

MODULES:
    resource-group      Resource group module tests
    container-registry  Container registry module tests
    key-vault           Key vault module tests
    observability       Log Analytics + App Insights tests
    container-app       Container Apps module tests

EXAMPLES:
    # Run all tests
    ./run-tests.sh

    # Run only validation tests (fast, no Azure resources created)
    ./run-tests.sh --short

    # Run tests for specific module
    ./run-tests.sh --module resource-group

    # Run with verbose output and custom timeout
    ./run-tests.sh --verbose --timeout 90

    # Run in parallel with 8 workers
    ./run-tests.sh --parallel 8
EOF
}

# Default values
TEST_MODE="all"
MODULE=""
VERBOSE=false
PARALLEL=4
TIMEOUT=60
SHORT_FLAG=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--all)
            TEST_MODE="all"
            shift
            ;;
        -s|--short)
            TEST_MODE="short"
            SHORT_FLAG="-short"
            shift
            ;;
        -m|--module)
            MODULE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -p|--parallel)
            PARALLEL="$2"
            shift 2
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Change to tests directory
cd "$(dirname "$0")"

print_header "Terraform Infrastructure Tests"

# Pre-flight checks
print_header "1. Pre-flight Checks"

# Check Go installation
if ! command -v go &> /dev/null; then
    log_error "Go is not installed"
    log_info "Install from: https://golang.org/dl/"
    exit 1
fi

GO_VERSION=$(go version | awk '{print $3}')
log_success "Go installed: $GO_VERSION"

# Check Terraform installation
if ! command -v terraform &> /dev/null; then
    log_error "Terraform is not installed"
    exit 1
fi

TF_VERSION=$(terraform version -json | grep -o '"terraform_version":"[^"]*' | cut -d'"' -f4)
log_success "Terraform installed: v$TF_VERSION"

# Check Azure authentication
if command -v az &> /dev/null; then
    AZURE_ACCOUNT=$(az account show --query "name" -o tsv 2>/dev/null || echo "")
    if [[ -n "$AZURE_ACCOUNT" ]]; then
        log_success "Azure CLI authenticated: $AZURE_ACCOUNT"

        SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
        export ARM_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
        log_info "Using subscription: $SUBSCRIPTION_ID"
    else
        log_error "Azure CLI not authenticated"
        log_info "Run: az login"
        exit 1
    fi
else
    log_error "Azure CLI not installed"
    exit 1
fi

# Check if running short tests
if [[ "$TEST_MODE" == "short" ]]; then
    log_warning "Running in SHORT mode - no actual Azure resources will be created"
fi

# Install dependencies
print_header "2. Installing Dependencies"

log_info "Running go mod download..."
if go mod download; then
    log_success "Dependencies installed"
else
    log_error "Failed to install dependencies"
    exit 1
fi

# Run tests
print_header "3. Running Tests"

# Build test command
TEST_CMD="go test"
TEST_FLAGS="-timeout ${TIMEOUT}m"

if [[ "$VERBOSE" == true ]]; then
    TEST_FLAGS="$TEST_FLAGS -v"
fi

TEST_FLAGS="$TEST_FLAGS -parallel $PARALLEL"

if [[ -n "$SHORT_FLAG" ]]; then
    TEST_FLAGS="$TEST_FLAGS $SHORT_FLAG"
fi

# Module-specific tests
if [[ -n "$MODULE" ]]; then
    case $MODULE in
        resource-group)
            TEST_PATTERN="TestResourceGroup"
            ;;
        container-registry)
            TEST_PATTERN="TestContainerRegistry"
            ;;
        key-vault)
            TEST_PATTERN="TestKeyVault"
            ;;
        observability)
            TEST_PATTERN="TestObservability"
            ;;
        container-app)
            TEST_PATTERN="TestContainerApp"
            ;;
        *)
            log_error "Unknown module: $MODULE"
            log_info "Valid modules: resource-group, container-registry, key-vault, observability, container-app"
            exit 1
            ;;
    esac
    TEST_FLAGS="$TEST_FLAGS -run $TEST_PATTERN"
    log_info "Running tests for module: $MODULE (pattern: $TEST_PATTERN)"
else
    log_info "Running all tests"
fi

echo ""
log_info "Test command: $TEST_CMD $TEST_FLAGS ./..."
echo ""

# Create logs directory
mkdir -p logs

# Run tests with output capture
TEST_OUTPUT_FILE="logs/test-output-$(date +%Y%m%d-%H%M%S).log"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  TEST OUTPUT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if $TEST_CMD $TEST_FLAGS ./... 2>&1 | tee "$TEST_OUTPUT_FILE"; then
    TEST_RESULT=0
else
    TEST_RESULT=$?
fi

# Summary
print_header "4. Test Summary"

if [[ $TEST_RESULT -eq 0 ]]; then
    log_success "All tests passed!"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  TESTS PASSED${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
else
    log_error "Some tests failed"
    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}  TESTS FAILED${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
fi

echo ""
log_info "Test output saved to: $TEST_OUTPUT_FILE"

# Show test statistics if available
if command -v grep &> /dev/null; then
    PASSED=$(grep -c "PASS:" "$TEST_OUTPUT_FILE" 2>/dev/null || echo "0")
    FAILED=$(grep -c "FAIL:" "$TEST_OUTPUT_FILE" 2>/dev/null || echo "0")

    if [[ $PASSED -gt 0 ]] || [[ $FAILED -gt 0 ]]; then
        echo ""
        echo "Statistics:"
        echo "  Passed: $PASSED"
        echo "  Failed: $FAILED"
    fi
fi

exit $TEST_RESULT
