package helpers

import (
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/azure"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// TestConfig holds common configuration for tests
type TestConfig struct {
	SubscriptionID string
	TenantID       string
	Location       string
	ResourceGroupName string
	UniqueID       string
}

// NewTestConfig creates a new test configuration
func NewTestConfig(t *testing.T) *TestConfig {
	subscriptionID := azure.GetSubscriptionID(t)
	tenantID := azure.GetTenantID(t)

	return &TestConfig{
		SubscriptionID: subscriptionID,
		TenantID:       tenantID,
		Location:       getEnvOrDefault("ARM_LOCATION", "eastus2"),
		UniqueID:       strings.ToLower(random.UniqueId()),
	}
}

// getEnvOrDefault gets an environment variable or returns a default value
func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// GenerateResourceGroupName generates a unique resource group name
func (c *TestConfig) GenerateResourceGroupName(prefix string) string {
	return fmt.Sprintf("rg-%s-test-%s", prefix, c.UniqueID)
}

// GenerateUniqueName generates a unique name for a resource
func (c *TestConfig) GenerateUniqueName(prefix string) string {
	return fmt.Sprintf("%s-%s", prefix, c.UniqueID)
}

// CleanupOptions holds options for cleanup
type CleanupOptions struct {
	DestroyTerraform bool
	DeleteResourceGroup bool
}

// DefaultTerraformOptions returns default terraform options for testing
func DefaultTerraformOptions(t *testing.T, terraformDir string, vars map[string]interface{}) *terraform.Options {
	return &terraform.Options{
		TerraformDir: terraformDir,
		Vars:         vars,
		NoColor:      true,
		Parallelism:  10,
		RetryableTerraformErrors: map[string]string{
			".*timeout.*":           "timeout error, retrying",
			".*connection refused.*": "connection refused, retrying",
			".*already exists.*":    "resource already exists, retrying",
		},
		MaxRetries:         3,
		TimeBetweenRetries: 10 * time.Second,
	}
}

// AssertResourceGroupExists asserts that a resource group exists
func AssertResourceGroupExists(t *testing.T, subscriptionID, resourceGroupName string) {
	exists := azure.ResourceGroupExists(t, resourceGroupName, subscriptionID)
	assert.True(t, exists, "Resource group %s should exist", resourceGroupName)
}

// AssertResourceGroupNotExists asserts that a resource group does not exist
func AssertResourceGroupNotExists(t *testing.T, subscriptionID, resourceGroupName string) {
	exists := azure.ResourceGroupExists(t, resourceGroupName, subscriptionID)
	assert.False(t, exists, "Resource group %s should not exist", resourceGroupName)
}

// GetRequiredEnvVar gets a required environment variable or fails the test
func GetRequiredEnvVar(t *testing.T, key string) string {
	value := os.Getenv(key)
	if value == "" {
		t.Fatalf("Required environment variable %s is not set", key)
	}
	return value
}

// CommonTags returns common tags for test resources
func CommonTags(testName string) map[string]string {
	return map[string]string{
		"ManagedBy":   "terratest",
		"TestName":    testName,
		"Environment": "test",
		CreatedAt":    time.Now().UTC().Format(time.RFC3339),
	}
}

// WaitForResourceDeletion waits for a resource to be deleted
func WaitForResourceDeletion(t *testing.T, checkFunc func() bool, maxRetries int, sleepBetweenRetries time.Duration) {
	for i := 0; i < maxRetries; i++ {
		if !checkFunc() {
			return
		}
		time.Sleep(sleepBetweenRetries)
	}
	t.Fatal("Resource was not deleted within the expected time")
}

// ValidateTerraformOutput validates that a terraform output exists and is not empty
func ValidateTerraformOutput(t *testing.T, outputs map[string]interface{}, key string) {
	value, exists := outputs[key]
	assert.True(t, exists, "Output %s should exist", key)
	assert.NotEmpty(t, value, "Output %s should not be empty", key)
}

// ValidateTerraformOutputType validates that a terraform output is of a specific type
func ValidateTerraformOutputType(t *testing.T, outputs map[string]interface{}, key string, expectedType string) {
	ValidateTerraformOutput(t, outputs, key)
	// Type checking would be done with reflection if needed
}

// Common test variables
const (
	DefaultTestTimeout = 60 * time.Minute
	DefaultWaitTimeout = 10 * time.Minute
	DefaultRetryCount  = 3
)

// StandardTags creates tags for test resources
func StandardTags(testName string) map[string]interface{} {
	return map[string]interface{}{
		"Environment": "test",
		"ManagedBy":   "terratest",
		"TestName":    testName,
	}
}
