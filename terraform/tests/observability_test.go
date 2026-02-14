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

// TestObservabilityBasic tests basic observability stack creation
func TestObservabilityBasic(t *testing.T) {
	t.Parallel()

	subscriptionID := azure.GetSubscriptionID(t)
	uniqueID := strings.ToLower(random.UniqueId())
	resourceGroupName := fmt.Sprintf("rg-obs-test-%s", uniqueID)
	logAnalyticsName := fmt.Sprintf("log-test-%s", uniqueID)
	appInsightsName := fmt.Sprintf("appi-test-%s", uniqueID)
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

	// Create observability stack
	obsOptions := &terraform.Options{
		TerraformDir: "../modules/observability",
		Vars: map[string]interface{}{
			"resource_group_name": resourceGroupName,
			"location":            location,
			"log_analytics_name":  logAnalyticsName,
			"app_insights_name":   appInsightsName,
			"tags": map[string]string{
				"Environment": "test",
				"ManagedBy":   "terratest",
			},
		},
	}
	defer terraform.Destroy(t, obsOptions)
	terraform.InitAndApply(t, obsOptions)

	// Verify Log Analytics exists
	workspace := azure.GetLogAnalyticsWorkspace(t, resourceGroupName, logAnalyticsName, subscriptionID)
	assert.NotNil(t, workspace, "Log Analytics workspace should exist")

	// Verify outputs
	outputs := terraform.OutputAll(t, obsOptions)

	// Log Analytics outputs
	assert.NotEmpty(t, outputs["log_analytics_workspace_id"], "Log Analytics ID should not be empty")
	assert.NotEmpty(t, outputs["log_analytics_workspace_name"], "Log Analytics name should not be empty")

	// Application Insights outputs
	assert.NotEmpty(t, outputs["app_insights_id"], "App Insights ID should not be empty")
	assert.NotEmpty(t, outputs["app_insights_name"], "App Insights name should not be empty")
	assert.NotEmpty(t, outputs["app_insights_connection_string"], "App Insights connection string should not be empty")
}

// TestObservabilityWithAvailabilityTest tests observability with availability test
func TestObservabilityWithAvailabilityTest(t *testing.T) {
	t.Parallel()

	if testing.Short() {
		t.Skip("Skipping slow test in short mode")
	}

	uniqueID := strings.ToLower(random.UniqueId())
	resourceGroupName := fmt.Sprintf("rg-obs-webtest-%s", uniqueID)
	logAnalyticsName := fmt.Sprintf("log-webtest-%s", uniqueID)
	appInsightsName := fmt.Sprintf("appi-webtest-%s", uniqueID)
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

	// Create observability with availability test
	obsOptions := &terraform.Options{
		TerraformDir: "../modules/observability",
		Vars: map[string]interface{}{
			"resource_group_name":     resourceGroupName,
			"location":                location,
			"log_analytics_name":      logAnalyticsName,
			"app_insights_name":       appInsightsName,
			"create_availability_test": true,
			"health_check_url":        "https://www.google.com/health",
			"tags": map[string]string{
				"Environment": "test",
			},
		},
	}
	defer terraform.Destroy(t, obsOptions)
	terraform.InitAndApply(t, obsOptions)

	// Verify deployment
	outputs := terraform.OutputAll(t, obsOptions)
	assert.NotEmpty(t, outputs["app_insights_id"], "App Insights should be created")
}

// TestObservabilitySamplingValidation tests sampling percentage validation
func TestObservabilitySamplingValidation(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name       string
		sampling   int
		shouldFail bool
	}{
		{"minimum_1", 1, false},
		{"maximum_100", 100, false},
		{"zero_invalid", 0, true},
		{"over_100_invalid", 101, true},
	}

	for _, tc := range testCases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			uniqueID := strings.ToLower(random.UniqueId())

			terraformOptions := &terraform.Options{
				TerraformDir: "../modules/observability",
				Vars: map[string]interface{}{
					"resource_group_name": "rg-nonexistent",
					"location":            "eastus2",
					"log_analytics_name":  fmt.Sprintf("log-%s", uniqueID),
					"app_insights_name":   fmt.Sprintf("appi-%s", uniqueID),
					"sampling_percentage": tc.sampling,
				},
			}

			if tc.shouldFail {
				_, err := terraform.PlanE(t, terraformOptions)
				assert.Error(t, err, "Expected validation error for sampling: %d", tc.sampling)
			}
		})
	}
}

// TestObservabilityApplicationTypeValidation tests application type validation
func TestObservabilityApplicationTypeValidation(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name            string
		applicationType string
		shouldFail      bool
	}{
		{"web_type", "web", false},
		{"other_type", "other", false},
		{"java_type", "java", false},
		{"nodejs_type", "Node.JS", false},
		{"invalid_type", "python", true},
	}

	for _, tc := range testCases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			uniqueID := strings.ToLower(random.UniqueId())

			terraformOptions := &terraform.Options{
				TerraformDir: "../modules/observability",
				Vars: map[string]interface{}{
					"resource_group_name": "rg-nonexistent",
					"location":            "eastus2",
					"log_analytics_name":  fmt.Sprintf("log-%s", uniqueID),
					"app_insights_name":   fmt.Sprintf("appi-%s", uniqueID),
					"application_type":    tc.applicationType,
				},
			}

			if tc.shouldFail {
				_, err := terraform.PlanE(t, terraformOptions)
				assert.Error(t, err, "Expected validation error for application type: %s", tc.applicationType)
			}
		})
	}
}

// TestObservabilityRetentionValidation tests retention validation
func TestObservabilityRetentionValidation(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name       string
		retention  int
		shouldFail bool
	}{
		{"minimum_7_days", 7, false},
		{"maximum_730_days", 730, false},
		{"too_few_days", 6, true},
	}

	for _, tc := range testCases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			uniqueID := strings.ToLower(random.UniqueId())

			terraformOptions := &terraform.Options{
				TerraformDir: "../modules/observability",
				Vars: map[string]interface{}{
					"resource_group_name":         "rg-nonexistent",
					"location":                    "eastus2",
					"log_analytics_name":          fmt.Sprintf("log-%s", uniqueID),
					"app_insights_name":           fmt.Sprintf("appi-%s", uniqueID),
					"log_analytics_retention_days": tc.retention,
				},
			}

			if tc.shouldFail {
				_, err := terraform.PlanE(t, terraformOptions)
				assert.Error(t, err, "Expected validation error for retention: %d", tc.retention)
			}
		})
	}
}
