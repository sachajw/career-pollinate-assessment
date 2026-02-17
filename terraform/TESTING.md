# Terraform Testing Guide

## Overview

This project has **comprehensive infrastructure testing** implemented using [Terratest](https://terratest.gruntwork.io/), a Go-based testing framework for infrastructure code.

## Test Coverage

### ✅ Modules with Tests

| Module | Test File | Coverage |
|--------|-----------|----------|
| **Resource Group** | `resource_group_test.go` | Basic creation, naming validation, tags, idempotency |
| **Container Registry** | `container_registry_test.go` | ACR creation, SKU tiers, admin access, diagnostics |
| **Key Vault** | `key_vault_test.go` | KV creation, RBAC, secrets, networking, diagnostics |
| **Observability** | `observability_test.go` | Log Analytics, Application Insights, retention |
| **Container App** | `container_app_test.go` | Container Apps, scaling, managed identity, ingress |

### Test Types

#### 1. **Unit Tests** (Fast - no Azure resources)
- Input validation
- Variable validation
- Naming convention checks
- Configuration validation

#### 2. **Integration Tests** (Slow - creates Azure resources)
- Full resource lifecycle (create/read/update/delete)
- Module composition
- Azure API integration
- End-to-end workflows

## Quick Start

### Prerequisites

```bash
# Install Go 1.21+
brew install go  # macOS
# or download from https://golang.org/dl/

# Install Terraform 1.5+
brew install terraform

# Authenticate to Azure
az login
az account set --subscription <subscription-id>
```

### Running Tests

```bash
cd terraform/tests

# Run ALL tests (creates real Azure resources - use caution!)
./run-tests.sh

# Run ONLY validation tests (fast, no resources created)
./run-tests.sh --short

# Run tests for a specific module
./run-tests.sh --module resource-group
./run-tests.sh --module key-vault

# Run with verbose output
./run-tests.sh --verbose

# Run with custom timeout (useful for slow connections)
./run-tests.sh --timeout 90

# Run tests in parallel (faster execution)
./run-tests.sh --parallel 8
```

## Test Architecture

### Directory Structure

```
terraform/
├── TESTING.md                  # This file
└── tests/
    ├── go.mod                      # Go module definition
    ├── go.sum                      # Dependencies lock file
    ├── README.md                   # Detailed testing documentation
    ├── run-tests.sh                # Test runner script
    ├── logs/                       # Test output logs
    ├── helpers/
    │   └── azure.go                # Azure-specific test utilities
    ├── resource_group_test.go      # Resource group tests
    ├── container_registry_test.go  # ACR tests
    ├── key_vault_test.go           # Key Vault tests
    ├── observability_test.go       # Observability stack tests
    └── container_app_test.go       # Container Apps tests
```

### Example Test: Resource Group

```go
func TestResourceGroupBasic(t *testing.T) {
    t.Parallel()

    // Arrange - Setup test data
    subscriptionID := azure.GetSubscriptionID(t)
    uniqueID := random.UniqueId()
    resourceGroupName := fmt.Sprintf("rg-test-%s", uniqueID)

    terraformOptions := &terraform.Options{
        TerraformDir: "../modules/resource-group",
        Vars: map[string]interface{}{
            "name":     resourceGroupName,
            "location": "eastus2",
            "tags":     map[string]string{"Environment": "test"},
        },
    }

    // Act - Deploy infrastructure
    defer terraform.Destroy(t, terraformOptions)
    terraform.InitAndApply(t, terraformOptions)

    // Assert - Verify resources
    exists := azure.ResourceGroupExists(t, resourceGroupName, subscriptionID)
    assert.True(t, exists)

    outputName := terraform.Output(t, terraformOptions, "resource_group_name")
    assert.Equal(t, resourceGroupName, outputName)
}
```

## CI/CD Integration

### Azure DevOps Pipeline

Tests can be integrated into the infrastructure pipeline:

```yaml
# Add to pipelines/azure-pipelines-infra.yml

- stage: Test
  displayName: 'Terraform Tests'
  dependsOn: []
  jobs:
    - job: Terratest
      pool: Default
      steps:
        - task: GoTool@0
          inputs:
            version: '1.21'

        - script: |
            cd terraform/tests
            go mod download
            go test -v -timeout 60m -short ./...
          displayName: 'Run Terratest (validation only)'
          env:
            ARM_SUBSCRIPTION_ID: $(ARM_SUBSCRIPTION_ID)
            ARM_TENANT_ID: $(ARM_TENANT_ID)
            ARM_CLIENT_ID: $(ARM_CLIENT_ID)
            ARM_CLIENT_SECRET: $(ARM_CLIENT_SECRET)
```

### GitHub Actions

```yaml
name: Terraform Tests

on:
  pull_request:
    paths:
      - 'terraform/**'
  push:
    branches: [main]

jobs:
  terratest:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-go@v4
        with:
          go-version: '1.21'

      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Run Terratest
        run: |
          cd terraform/tests
          go test -v -timeout 60m -short ./...
        env:
          ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
          ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
```

## Cost Optimization

### Minimize Testing Costs

1. **Use Short Tests for PR Checks**
   ```bash
   # Validation only - no Azure resources
   go test -short -timeout 10m ./...
   ```

2. **Run Integration Tests Nightly**
   - Schedule full integration tests during off-hours
   - Run on dedicated test subscription

3. **Automatic Cleanup**
   - Terratest automatically destroys resources via `defer terraform.Destroy(t, terraformOptions)`
   - Failed tests leave resources for debugging (manual cleanup needed)

4. **Use Cheap SKUs**
   - Tests use Basic/Standard SKUs where possible
   - Scale-to-zero for Container Apps in test

## Best Practices

### Writing Tests

1. **Use `t.Parallel()`** - Run independent tests in parallel
2. **Unique Naming** - Use `random.UniqueId()` to avoid naming conflicts
3. **Defer Cleanup** - Always use `defer terraform.Destroy()`
4. **Clear Assertions** - Use testify for readable test failures
5. **Test Isolation** - Each test should be independent

### Example Pattern

```go
func TestMyModule(t *testing.T) {
    t.Parallel()  // Run in parallel

    // 1. Arrange - Setup
    uniqueID := random.UniqueId()
    options := terraform.Options{...}

    // 2. Act - Deploy
    defer terraform.Destroy(t, options)  // Cleanup
    terraform.InitAndApply(t, options)

    // 3. Assert - Verify
    output := terraform.Output(t, options, "my_output")
    assert.NotEmpty(t, output)
}
```

## Troubleshooting

### Common Issues

#### 1. Authentication Errors

```bash
# Solution: Login to Azure CLI
az login
az account show  # Verify subscription
```

#### 2. Timeout Errors

```bash
# Solution: Increase timeout
./run-tests.sh --timeout 120
```

#### 3. Resource Quota Exceeded

```bash
# Solution: Check Azure quotas
az vm list-usage --location eastus2 --output table

# Or use different region
export ARM_LOCATION="westus2"
```

#### 4. Test Failures Leave Resources

```bash
# Solution: Manual cleanup
az group list --query "[?starts_with(name, 'rg-test-')].name" -o tsv | \
  xargs -I {} az group delete --name {} --yes --no-wait
```

#### 5. Go Module Issues

```bash
# Solution: Clean and reinstall
cd terraform/tests
go clean -modcache
go mod download
go mod tidy
```

## Test Metrics

### Execution Times (Approximate)

| Test Type | Duration | Resources Created |
|-----------|----------|-------------------|
| Short (validation) | 2-5 min | 0 (no Azure resources) |
| Resource Group | 3-5 min | 1 resource group |
| Container Registry | 10-15 min | ACR + diagnostics |
| Key Vault | 8-12 min | Key Vault + RBAC |
| Observability | 10-15 min | Log Analytics + App Insights |
| Container App | 15-20 min | Container App + dependencies |
| **Full Suite** | **45-60 min** | **~15-20 resources** |

### Cost per Test Run (Approximate)

- **Short tests**: $0.00 (no resources)
- **Single module test**: $0.10 - $0.50
- **Full test suite**: $1.00 - $3.00

*Costs vary by region and test duration. Resources are destroyed after tests.*

## Advanced Usage

### Running Specific Tests

```bash
# Run only naming convention tests
go test -v -run TestNamingConvention -timeout 10m ./...

# Run all Key Vault tests
go test -v -run TestKeyVault -timeout 30m ./...

# Run with race detector
go test -v -race -timeout 60m ./...
```

### Debugging Failed Tests

```bash
# Run with maximum verbosity
TF_LOG=DEBUG go test -v -run TestMyFailingTest ./...

# Keep resources after failure for investigation
# (Comment out defer terraform.Destroy() line)

# Check test logs
cat logs/test-output-*.log
```

### Custom Environment Variables

```bash
# Override default location
export ARM_LOCATION="westus2"

# Use service principal authentication
export ARM_CLIENT_ID="xxx"
export ARM_CLIENT_SECRET="xxx"
export ARM_TENANT_ID="xxx"
export ARM_SUBSCRIPTION_ID="xxx"

# Run tests
./run-tests.sh
```

## Next Steps

1. ✅ **Review test coverage** - Check `terraform/tests/` directory
2. ✅ **Run validation tests** - `./run-tests.sh --short`
3. ⚠️ **Run integration tests** - `./run-tests.sh` (creates Azure resources!)
4. 📊 **Review test output** - Check `logs/` directory
5. 🔄 **Add to CI/CD** - Integrate into Azure DevOps pipeline

## References

- [Terratest Documentation](https://terratest.gruntwork.io/)
- [Terratest Azure Module](https://pkg.go.dev/github.com/gruntwork-io/terratest/modules/azure)
- [Go Testing Package](https://golang.org/pkg/testing/)
- [Testify Assertions](https://pkg.go.dev/github.com/stretchr/testify/assert)

---

**Questions or Issues?** See `terraform/tests/README.md` for detailed documentation.
