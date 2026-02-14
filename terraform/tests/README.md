# Terratest - Infrastructure Testing Framework

This directory contains Terratest-based integration tests for the Terraform modules.

## Overview

Terratest is a Go library that provides patterns and helper functions for testing infrastructure.

## Prerequisites

- Go 1.21 or later
- Terraform >= 1.5.0
- Azure subscription with appropriate permissions
- Azure CLI authenticated (`az login`)

## Test Structure

```
tests/
├── go.mod              # Go module definition
├── go.sum              # Go dependencies checksum
├── README.md           # This file
├── resource_group_test.go    # Tests for resource-group module
├── container_registry_test.go # Tests for container-registry module
├── key_vault_test.go         # Tests for key-vault module
├── observability_test.go     # Tests for observability module
├── container_app_test.go     # Tests for container-app module
└── helpers/
    └── azure.go        # Azure-specific test helpers
```

## Running Tests

### Run All Tests

```bash
cd terraform/tests
go test -v -timeout 60m
```

### Run Specific Test

```bash
go test -v -run TestResourceGroup -timeout 30m
```

### Run with Short Tests Only

```bash
go test -v -short -timeout 10m
```

### Run with Verbose Output

```bash
go test -v -timeout 60m 2>&1 | tee test-output.log
```

## Environment Variables

| Variable              | Description                 | Required          |
| --------------------- | --------------------------- | ----------------- |
| `ARM_SUBSCRIPTION_ID` | Azure subscription ID       | Yes               |
| `ARM_TENANT_ID`       | Azure tenant ID             | Yes               |
| `ARM_CLIENT_ID`       | Service principal client ID | No (use CLI auth) |
| `ARM_CLIENT_SECRET`   | Service principal secret    | No (use CLI auth) |

## Test Categories

### Unit Tests (Fast)

- Input validation tests
- Variable validation tests
- Output structure tests

### Integration Tests (Slow)

- Resource creation/deletion tests
- Module composition tests
- End-to-end tests

## Best Practices

1. **Unique Naming**: Tests use random suffixes to avoid naming conflicts
2. **Cleanup**: Always clean up resources after tests
3. **Timeouts**: Set appropriate timeouts for long-running operations
4. **Parallelism**: Use `t.Parallel()` for independent tests
5. **Assertions**: Use testify assertions for clear error messages

## CI/CD Integration

Tests are designed to run in CI/CD pipelines:

```yaml
# Example GitHub Actions
- name: Run Terratest
  run: |
    cd terraform/tests
    go test -v -timeout 60m ./...
  env:
    ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
    ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
```

## Adding New Tests

1. Create a new test file: `module_name_test.go`
2. Import terratest modules
3. Define test function with `Test` prefix
4. Use helper functions for common operations
5. Ensure proper cleanup with `defer`

## Troubleshooting

### Common Issues

1. **Authentication Errors**

   ```bash
   az login
   az account set --subscription <subscription-id>
   ```

2. **Quota Exceeded**
   - Check Azure quotas in the region
   - Use a different region

3. **Timeout Errors**
   - Increase timeout value
   - Check Azure service health

## References

- [Terratest Documentation](https://terratest.gruntwork.io/)
- [Azure Terraform Provider](https://registry.terraform.io/providers/hashicorp/azurerm/)
- [Go Testing Package](https://golang.org/pkg/testing/)
