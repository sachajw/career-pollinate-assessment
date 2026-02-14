package test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/azure"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// TestContainerRegistryBasic tests basic ACR creation
func TestContainerRegistryBasic(t *testing.T) {
	t.Parallel()

	subscriptionID := azure.GetSubscriptionID(t)
	uniqueID := strings.ToLower(random.UniqueId())
	resourceGroupName := fmt.Sprintf("rg-acr-test-%s", uniqueID)
	acrName := fmt.Sprintf("acrtest%s", uniqueID)
	location := "eastus2"

	// First create resource group
	rgOptions := &terraform.Options{
		TerraformDir: "../modules/resource-group",
		Vars: map[string]interface{}{
			"name":     resourceGroupName,
			"location": location,
			"tags": map[string]string{
				"Environment": "test",
				"ManagedBy":   "terratest",
			},
		},
	}
	defer terraform.Destroy(t, rgOptions)
	terraform.InitAndApply(t, rgOptions)

	// Create ACR
	acrOptions := &terraform.Options{
		TerraformDir: "../modules/container-registry",
		Vars: map[string]interface{}{
			"name":                acrName,
			"resource_group_name": resourceGroupName,
			"location":            location,
			"sku":                 "Basic",
			"tags": map[string]string{
				"Environment": "test",
				"ManagedBy":   "terratest",
			},
		},
	}
	defer terraform.Destroy(t, acrOptions)
	terraform.InitAndApply(t, acrOptions)

	// Verify ACR exists
	acr := azure.GetContainerRegistry(t, resourceGroupName, acrName, subscriptionID)
	assert.NotNil(t, acr, "Container Registry should exist")

	// Verify outputs
	outputs := terraform.OutputAll(t, acrOptions)
	assert.NotEmpty(t, outputs["id"], "ID output should not be empty")
	assert.NotEmpty(t, outputs["name"], "Name output should not be empty")
	assert.NotEmpty(t, outputs["login_server"], "Login server output should not be empty")

	// Verify login server format
	loginServer := outputs["login_server"].(string)
	assert.Contains(t, loginServer, acrName, "Login server should contain ACR name")
	assert.Contains(t, loginServer, ".azurecr.io", "Login server should be Azure Container Registry")
}

// TestContainerRegistrySkuValidation tests SKU validation
func TestContainerRegistrySkuValidation(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name       string
		sku        string
		shouldFail bool
	}{
		{"basic_sku", "Basic", false},
		{"standard_sku", "Standard", false},
		{"premium_sku", "Premium", false},
		{"invalid_sku", "Enterprise", true},
	}

	for _, tc := range testCases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			uniqueID := strings.ToLower(random.UniqueId())
			acrName := fmt.Sprintf("acrtest%s", uniqueID)

			terraformOptions := &terraform.Options{
				TerraformDir: "../modules/container-registry",
				Vars: map[string]interface{}{
					"name":                acrName,
					"resource_group_name": "rg-nonexistent", // Will fail before this
					"location":            "eastus2",
					"sku":                 tc.sku,
				},
			}

			if tc.shouldFail {
				_, err := terraform.PlanE(t, terraformOptions)
				assert.Error(t, err, "Expected validation error for SKU: %s", tc.sku)
			}
		})
	}
}

// TestContainerRegistryNameValidation tests name validation
func TestContainerRegistryNameValidation(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name        string
		acrName     string
		shouldFail  bool
		description string
	}{
		{
			name:        "valid_name",
			acrName:     "acrvalid123",
			shouldFail:  false,
			description: "Valid alphanumeric name",
		},
		{
			name:        "too_short",
			acrName:     "acr",
			shouldFail:  true,
			description: "Name too short (less than 5 chars)",
		},
		{
			name:        "with_uppercase",
			acrName:     "ACRTest",
			shouldFail:  true,
			description: "Name with uppercase letters",
		},
		{
			name:        "with_hyphen",
			acrName:     "acr-test",
			shouldFail:  true,
			description: "Name with hyphen",
		},
	}

	for _, tc := range testCases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			terraformOptions := &terraform.Options{
				TerraformDir: "../modules/container-registry",
				Vars: map[string]interface{}{
					"name":                tc.acrName,
					"resource_group_name": "rg-nonexistent",
					"location":            "eastus2",
					"sku":                 "Basic",
				},
			}

			if tc.shouldFail {
				_, err := terraform.PlanE(t, terraformOptions)
				assert.Error(t, err, "Expected validation error for name: %s", tc.acrName)
			}
		})
	}
}

// TestContainerRegistryWithDiagnostics tests ACR with diagnostic settings
func TestContainerRegistryWithDiagnostics(t *testing.T) {
	t.Parallel()

	// This test is marked as slow because it requires Log Analytics
	if testing.Short() {
		t.Skip("Skipping slow test in short mode")
	}

	subscriptionID := azure.GetSubscriptionID(t)
	uniqueID := strings.ToLower(random.UniqueId())
	resourceGroupName := fmt.Sprintf("rg-acr-diag-test-%s", uniqueID)
	acrName := fmt.Sprintf("acrdiag%s", uniqueID)
	location := "eastus2"

	// Create resource group
	rgOptions := &terraform.Options{
		TerraformDir: "../modules/resource-group",
		Vars: map[string]interface{}{
			"name":     resourceGroupName,
			"location": location,
		},
	}
	defer terraform.Destroy(t, rgOptions)
	terraform.InitAndApply(t, rgOptions)

	// Create Log Analytics workspace
	workspaceID := createLogAnalyticsWorkspace(t, resourceGroupName, location, uniqueID)

	// Create ACR with diagnostics
	acrOptions := &terraform.Options{
		TerraformDir: "../modules/container-registry",
		Vars: map[string]interface{}{
			"name":                      acrName,
			"resource_group_name":       resourceGroupName,
			"location":                  location,
			"sku":                       "Basic",
			"log_analytics_workspace_id": workspaceID,
			"tags": map[string]string{
				"Environment": "test",
			},
		},
	}
	defer terraform.Destroy(t, acrOptions)
	terraform.InitAndApply(t, acrOptions)

	// Verify ACR exists
	acr := azure.GetContainerRegistry(t, resourceGroupName, acrName, subscriptionID)
	assert.NotNil(t, acr, "Container Registry should exist")
}

// Helper function to create Log Analytics workspace
func createLogAnalyticsWorkspace(t *testing.T, resourceGroupName, location, uniqueID string) string {
	workspaceName := fmt.Sprintf("log-test-%s", uniqueID)

	workspaceOptions := &terraform.Options{
		TerraformDir: "../modules/observability",
		Vars: map[string]interface{}{
			"resource_group_name":  resourceGroupName,
			"location":             location,
			"log_analytics_name":   workspaceName,
			"app_insights_name":    fmt.Sprintf("appi-test-%s", uniqueID),
			"tags": map[string]string{
				"Test": "true",
			},
		},
	}

	terraform.InitAndApply(t, workspaceOptions)
	return terraform.Output(t, workspaceOptions, "log_analytics_workspace_id")
}
