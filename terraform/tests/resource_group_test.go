package test

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/azure"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// TestResourceGroupBasic tests the basic creation of a resource group
func TestResourceGroupBasic(t *testing.T) {
	t.Parallel()

	// Arrange
	subscriptionID := azure.GetSubscriptionID(t)
	uniqueID := strings.ToLower(random.UniqueId())
	resourceGroupName := fmt.Sprintf("rg-test-%s", uniqueID)
	location := "eastus2"

	terraformOptions := &terraform.Options{
		TerraformDir: "../modules/resource-group/examples/complete",
		Vars: map[string]interface{}{
			"name":     resourceGroupName,
			"location": location,
			"tags": map[string]string{
				"Environment": "test",
				"ManagedBy":   "terratest",
				"TestRun":     uniqueID,
			},
		},
	}

	// Act - Deploy
	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Assert
	// Verify resource group exists
	exists := azure.ResourceGroupExists(t, resourceGroupName, subscriptionID)
	assert.True(t, exists, "Resource group should exist")

	// Verify outputs
	resourceGroupID := terraform.Output(t, terraformOptions, "resource_group_id")
	assert.NotEmpty(t, resourceGroupID, "Resource group ID should not be empty")

	outputName := terraform.Output(t, terraformOptions, "resource_group_name")
	assert.Equal(t, resourceGroupName, outputName, "Output name should match input name")

	outputLocation := terraform.Output(t, terraformOptions, "resource_group_location")
	assert.Equal(t, location, outputLocation, "Output location should match input location")
}

// TestResourceGroupNamingConvention tests that naming convention validation works
func TestResourceGroupNamingConvention(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name        string
		inputName   string
		shouldFail  bool
		description string
	}{
		{
			name:        "valid_name",
			inputName:   "rg-valid-name",
			shouldFail:  false,
			description: "Valid name with rg- prefix",
		},
		{
			name:        "invalid_name_no_prefix",
			inputName:   "invalid-name",
			shouldFail:  true,
			description: "Invalid name without rg- prefix",
		},
		{
			name:        "invalid_name_wrong_prefix",
			inputName:   "my-rg-name",
			shouldFail:  true,
			description: "Invalid name with wrong prefix",
		},
	}

	for _, tc := range testCases {
		tc := tc // Capture range variable
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			terraformOptions := &terraform.Options{
				TerraformDir: "../modules/resource-group",
				Vars: map[string]interface{}{
					"name":     tc.inputName,
					"location": "eastus2",
					"tags": map[string]string{
						"Test": "true",
					},
				},
			}

			if tc.shouldFail {
				// For validation errors, we can use terraform.Plan
				// The validation should fail during plan
				_, err := terraform.PlanE(t, terraformOptions)
				if err == nil {
					// If plan succeeded, the apply should fail
					_, err = terraform.InitAndApplyE(t, terraformOptions)
				}
				assert.Error(t, err, "Expected validation error for name: %s", tc.inputName)
			}
		})
	}
}

// TestResourceGroupLocationValidation tests that location validation works
func TestResourceGroupLocationValidation(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name         string
		location     string
		shouldFail   bool
		description  string
	}{
		{
			name:        "valid_location_eastus2",
			location:    "eastus2",
			shouldFail:  false,
			description: "Valid location: eastus2",
		},
		{
			name:        "valid_location_westus2",
			location:    "westus2",
			shouldFail:  false,
			description: "Valid location: westus2",
		},
		{
			name:        "valid_location_centralus",
			location:    "centralus",
			shouldFail:  false,
			description: "Valid location: centralus",
		},
		{
			name:        "invalid_location",
			location:    "westeurope",
			shouldFail:  true,
			description: "Invalid location: westeurope",
		},
	}

	for _, tc := range testCases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			uniqueID := strings.ToLower(random.UniqueId())
			resourceGroupName := fmt.Sprintf("rg-test-%s", uniqueID)

			terraformOptions := &terraform.Options{
				TerraformDir: "../modules/resource-group",
				Vars: map[string]interface{}{
					"name":     resourceGroupName,
					"location": tc.location,
					"tags": map[string]string{
						"Test": "true",
					},
				},
			}

			if tc.shouldFail {
				_, err := terraform.PlanE(t, terraformOptions)
				if err == nil {
					_, err = terraform.InitAndApplyE(t, terraformOptions)
				}
				assert.Error(t, err, "Expected validation error for location: %s", tc.location)
			}
		})
	}
}

// TestResourceGroupWithTags tests resource group creation with custom tags
func TestResourceGroupWithTags(t *testing.T) {
	t.Parallel()

	subscriptionID := azure.GetSubscriptionID(t)
	uniqueID := strings.ToLower(random.UniqueId())
	resourceGroupName := fmt.Sprintf("rg-test-%s", uniqueID)
	location := "eastus2"

	customTags := map[string]interface{}{
		"Environment": "test",
		"ManagedBy":   "terratest",
		"Project":     "terraform-modules",
		"CostCenter":  "engineering",
		"TestRun":     uniqueID,
	}

	terraformOptions := &terraform.Options{
		TerraformDir: "../modules/resource-group/examples/complete",
		Vars: map[string]interface{}{
			"name":     resourceGroupName,
			"location": location,
			"tags":     customTags,
		},
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Verify resource group exists and has correct tags
	rg := azure.GetAResourceGroup(t, resourceGroupName, subscriptionID)
	assert.NotNil(t, rg, "Resource group should exist")

	// Verify tags were applied
	if rg.Tags != nil {
		for key, value := range customTags {
			if tagValue, exists := (*rg.Tags)[key]; exists {
				assert.Equal(t, value, *tagValue, "Tag %s should have correct value", key)
			}
		}
	}
}

// TestResourceGroupOutputs tests that all outputs are correctly set
func TestResourceGroupOutputs(t *testing.T) {
	t.Parallel()

	uniqueID := strings.ToLower(random.UniqueId())
	resourceGroupName := fmt.Sprintf("rg-test-%s", uniqueID)
	location := "eastus2"

	terraformOptions := &terraform.Options{
		TerraformDir: "../modules/resource-group/examples/complete",
		Vars: map[string]interface{}{
			"name":     resourceGroupName,
			"location": location,
			"tags": map[string]string{
				"Test": "true",
			},
		},
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Verify all outputs exist
	outputs := terraform.OutputAll(t, terraformOptions)

	requiredOutputs := []string{
		"resource_group_id",
		"resource_group_name",
		"resource_group_location",
	}

	for _, output := range requiredOutputs {
		_, exists := outputs[output]
		assert.True(t, exists, "Output %s should exist", output)
	}

	// Verify output format
	resourceGroupID := outputs["resource_group_id"].(string)
	assert.Contains(t, resourceGroupID, "/subscriptions/", "Resource group ID should be in correct format")
	assert.Contains(t, resourceGroupID, "/resourceGroups/"+resourceGroupName, "Resource group ID should contain resource group name")
}
