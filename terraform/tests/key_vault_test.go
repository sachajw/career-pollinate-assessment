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

// TestKeyVaultBasic tests basic Key Vault creation
func TestKeyVaultBasic(t *testing.T) {
	t.Parallel()

	subscriptionID := azure.GetSubscriptionID(t)
	uniqueID := strings.ToLower(random.UniqueId())
	resourceGroupName := fmt.Sprintf("rg-kv-test-%s", uniqueID)
	keyVaultName := fmt.Sprintf("kv-test-%s", uniqueID)
	location := "eastus2"

	// Create resource group
	rgOptions := &terraform.Options{
		TerraformDir: "../modules/resource-group",
		Vars: map[string]interface{}{
			"name":     resourceGroupName,
			"location": location,
			"tags": map[string]string{
				"Environment": "test",
			},
		},
	}
	defer terraform.Destroy(t, rgOptions)
	terraform.InitAndApply(t, rgOptions)

	// Create Key Vault
	kvOptions := &terraform.Options{
		TerraformDir: "../modules/key-vault",
		Vars: map[string]interface{}{
			"name":                keyVaultName,
			"resource_group_name": resourceGroupName,
			"location":            location,
			"sku_name":            "standard",
			"tags": map[string]string{
				"Environment": "test",
				"ManagedBy":   "terratest",
			},
		},
	}
	defer terraform.Destroy(t, kvOptions)
	terraform.InitAndApply(t, kvOptions)

	// Verify Key Vault exists
	kv := azure.GetKeyVault(t, resourceGroupName, keyVaultName, subscriptionID)
	assert.NotNil(t, kv, "Key Vault should exist")

	// Verify outputs
	outputs := terraform.OutputAll(t, kvOptions)
	assert.NotEmpty(t, outputs["id"], "ID output should not be empty")
	assert.NotEmpty(t, outputs["name"], "Name output should not be empty")
	assert.NotEmpty(t, outputs["vault_uri"], "Vault URI output should not be empty")

	// Verify vault URI format
	vaultURI := outputs["vault_uri"].(string)
	assert.Contains(t, vaultURI, "https://", "Vault URI should use HTTPS")
	assert.Contains(t, vaultURI, ".vault.azure.net", "Vault URI should be Azure Key Vault")
}

// TestKeyVaultNameValidation tests Key Vault name validation
func TestKeyVaultNameValidation(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name        string
		kvName      string
		shouldFail  bool
		description string
	}{
		{
			name:        "valid_name",
			kvName:      "kv-valid-name",
			shouldFail:  false,
			description: "Valid Key Vault name",
		},
		{
			name:        "too_short",
			kvName:      "kv",
			shouldFail:  true,
			description: "Name too short",
		},
		{
			name:        "too_long",
			kvName:      "kv-this-name-is-way-too-long-for-azure-key-vault",
			shouldFail:  true,
			description: "Name too long",
		},
		{
			name:        "starts_with_number",
			kvName:      "kv-123-test",
			shouldFail:  true,
			description: "Name starts with number",
		},
		{
			name:        "with_underscore",
			kvName:      "kv_test_name",
			shouldFail:  true,
			description: "Name contains underscore",
		},
	}

	for _, tc := range testCases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			terraformOptions := &terraform.Options{
				TerraformDir: "../modules/key-vault",
				Vars: map[string]interface{}{
					"name":                tc.kvName,
					"resource_group_name": "rg-nonexistent",
					"location":            "eastus2",
				},
			}

			if tc.shouldFail {
				_, err := terraform.PlanE(t, terraformOptions)
				assert.Error(t, err, "Expected validation error for name: %s", tc.kvName)
			}
		})
	}
}

// TestKeyVaultSkuValidation tests SKU validation
func TestKeyVaultSkuValidation(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name       string
		sku        string
		shouldFail bool
	}{
		{"standard_sku", "standard", false},
		{"premium_sku", "premium", false},
		{"invalid_sku", "enterprise", true},
	}

	for _, tc := range testCases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			uniqueID := strings.ToLower(random.UniqueId())
			kvName := fmt.Sprintf("kvtest%s", uniqueID)

			terraformOptions := &terraform.Options{
				TerraformDir: "../modules/key-vault",
				Vars: map[string]interface{}{
					"name":                kvName,
					"resource_group_name": "rg-nonexistent",
					"location":            "eastus2",
					"sku_name":            tc.sku,
				},
			}

			if tc.shouldFail {
				_, err := terraform.PlanE(t, terraformOptions)
				assert.Error(t, err, "Expected validation error for SKU: %s", tc.sku)
			}
		})
	}
}

// TestKeyVaultRetentionValidation tests soft delete retention validation
func TestKeyVaultRetentionValidation(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name         string
		retentionDays int
		shouldFail   bool
	}{
		{"minimum_7_days", 7, false},
		{"maximum_90_days", 90, false},
		{"too_few_days", 6, true},
		{"too_many_days", 91, true},
	}

	for _, tc := range testCases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			uniqueID := strings.ToLower(random.UniqueId())
			kvName := fmt.Sprintf("kvtest%s", uniqueID)

			terraformOptions := &terraform.Options{
				TerraformDir: "../modules/key-vault",
				Vars: map[string]interface{}{
					"name":                       kvName,
					"resource_group_name":        "rg-nonexistent",
					"location":                   "eastus2",
					"soft_delete_retention_days": tc.retentionDays,
				},
			}

			if tc.shouldFail {
				_, err := terraform.PlanE(t, terraformOptions)
				assert.Error(t, err, "Expected validation error for retention days: %d", tc.retentionDays)
			}
		})
	}
}

// TestKeyVaultWithNetworkAcls tests Key Vault with network ACLs
func TestKeyVaultWithNetworkAcls(t *testing.T) {
	t.Parallel()

	if testing.Short() {
		t.Skip("Skipping slow test in short mode")
	}

	subscriptionID := azure.GetSubscriptionID(t)
	uniqueID := strings.ToLower(random.UniqueId())
	resourceGroupName := fmt.Sprintf("rg-kv-acl-test-%s", uniqueID)
	keyVaultName := fmt.Sprintf("kv-acl-%s", uniqueID)
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

	// Create Key Vault with network ACLs
	kvOptions := &terraform.Options{
		TerraformDir: "../modules/key-vault",
		Vars: map[string]interface{}{
			"name":                        keyVaultName,
			"resource_group_name":         resourceGroupName,
			"location":                    location,
			"sku_name":                    "standard",
			"network_acls_enabled":        true,
			"network_acls_default_action": "Deny",
			"network_acls_bypass":         "AzureServices",
			"tags": map[string]string{
				"Environment": "test",
			},
		},
	}
	defer terraform.Destroy(t, kvOptions)
	terraform.InitAndApply(t, kvOptions)

	// Verify Key Vault exists
	kv := azure.GetKeyVault(t, resourceGroupName, keyVaultName, subscriptionID)
	assert.NotNil(t, kv, "Key Vault should exist")
}
