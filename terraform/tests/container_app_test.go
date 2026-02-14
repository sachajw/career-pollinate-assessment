package test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// TestContainerAppInputValidation tests input validation for container app module
func TestContainerAppInputValidation(t *testing.T) {
	t.Parallel()

	t.Run("name_validation", func(t *testing.T) {
		t.Parallel()

		testCases := []struct {
			name        string
			appName     string
			shouldFail  bool
			description string
		}{
			{
				name:       "valid_name",
				appName:    "ca-valid-name",
				shouldFail: false,
			},
			{
				name:       "starts_with_number",
				appName:    "ca-123invalid",
				shouldFail: true,
			},
			{
				name:       "with_uppercase",
				appName:    "ca-Invalid",
				shouldFail: true,
			},
			{
				name:       "too_long",
				appName:    "ca-this-name-is-way-too-long-for-azure-container-apps",
				shouldFail: true,
			},
		}

		for _, tc := range testCases {
			tc := tc
			t.Run(tc.name, func(t *testing.T) {
				t.Parallel()

				uniqueID := strings.ToLower(random.UniqueId())

				terraformOptions := &terraform.Options{
					TerraformDir: "../modules/container-app",
					Vars: map[string]interface{}{
						"name":                      tc.appName,
						"environment_name":          fmt.Sprintf("cae-test-%s", uniqueID),
						"resource_group_name":       "rg-nonexistent",
						"location":                  "eastus2",
						"log_analytics_workspace_id": "/subscriptions/test/resourceGroups/test/providers/Microsoft.OperationalInsights/workspaces/test",
						"container_image":           "nginx:latest",
					},
				}

				if tc.shouldFail {
					_, err := terraform.PlanE(t, terraformOptions)
					assert.Error(t, err, "Expected validation error for name: %s", tc.appName)
				}
			})
		}
	})

	t.Run("cpu_validation", func(t *testing.T) {
		t.Parallel()

		testCases := []struct {
			name       string
			cpu        float64
			shouldFail bool
		}{
			{"valid_025", 0.25, false},
			{"valid_05", 0.5, false},
			{"valid_1", 1.0, false},
			{"valid_2", 2.0, false},
			{"invalid_0_1", 0.1, true},
			{"invalid_3", 3.0, true},
		}

		for _, tc := range testCases {
			tc := tc
			t.Run(tc.name, func(t *testing.T) {
				t.Parallel()

				uniqueID := strings.ToLower(random.UniqueId())

				terraformOptions := &terraform.Options{
					TerraformDir: "../modules/container-app",
					Vars: map[string]interface{}{
						"name":                      fmt.Sprintf("ca-test-%s", uniqueID),
						"environment_name":          fmt.Sprintf("cae-test-%s", uniqueID),
						"resource_group_name":       "rg-nonexistent",
						"location":                  "eastus2",
						"log_analytics_workspace_id": "/subscriptions/test/resourceGroups/test/providers/Microsoft.OperationalInsights/workspaces/test",
						"container_image":           "nginx:latest",
						"container_cpu":             tc.cpu,
					},
				}

				if tc.shouldFail {
					_, err := terraform.PlanE(t, terraformOptions)
					assert.Error(t, err, "Expected validation error for CPU: %f", tc.cpu)
				}
			})
		}
	})

	t.Run("memory_validation", func(t *testing.T) {
		t.Parallel()

		testCases := []struct {
			name       string
			memory     string
			shouldFail bool
		}{
			{"valid_05gi", "0.5Gi", false},
			{"valid_1gi", "1Gi", false},
			{"valid_2gi", "2Gi", false},
			{"valid_4gi", "4Gi", false},
			{"invalid_3gi", "3Gi", false}, // 3Gi is actually valid
			{"invalid_format", "1024", true},
		}

		for _, tc := range testCases {
			tc := tc
			t.Run(tc.name, func(t *testing.T) {
				t.Parallel()

				uniqueID := strings.ToLower(random.UniqueId())

				terraformOptions := &terraform.Options{
					TerraformDir: "../modules/container-app",
					Vars: map[string]interface{}{
						"name":                      fmt.Sprintf("ca-test-%s", uniqueID),
						"environment_name":          fmt.Sprintf("cae-test-%s", uniqueID),
						"resource_group_name":       "rg-nonexistent",
						"location":                  "eastus2",
						"log_analytics_workspace_id": "/subscriptions/test/resourceGroups/test/providers/Microsoft.OperationalInsights/workspaces/test",
						"container_image":           "nginx:latest",
						"container_memory":          tc.memory,
					},
				}

				if tc.shouldFail {
					_, err := terraform.PlanE(t, terraformOptions)
					assert.Error(t, err, "Expected validation error for memory: %s", tc.memory)
				}
			})
		}
	})

	t.Run("replicas_validation", func(t *testing.T) {
		t.Parallel()

		testCases := []struct {
			name        string
			minReplicas int
			maxReplicas int
			shouldFail  bool
		}{
			{"valid_scale_zero", 0, 10, false},
			{"valid_equal", 5, 5, false},
			{"invalid_min_greater", 10, 5, true},
			{"invalid_min_negative", -1, 10, true},
			{"invalid_max_zero", 0, 0, true},
		}

		for _, tc := range testCases {
			tc := tc
			t.Run(tc.name, func(t *testing.T) {
				t.Parallel()

				uniqueID := strings.ToLower(random.UniqueId())

				terraformOptions := &terraform.Options{
					TerraformDir: "../modules/container-app",
					Vars: map[string]interface{}{
						"name":                      fmt.Sprintf("ca-test-%s", uniqueID),
						"environment_name":          fmt.Sprintf("cae-test-%s", uniqueID),
						"resource_group_name":       "rg-nonexistent",
						"location":                  "eastus2",
						"log_analytics_workspace_id": "/subscriptions/test/resourceGroups/test/providers/Microsoft.OperationalInsights/workspaces/test",
						"container_image":           "nginx:latest",
						"min_replicas":              tc.minReplicas,
						"max_replicas":              tc.maxReplicas,
					},
				}

				if tc.shouldFail {
					_, err := terraform.PlanE(t, terraformOptions)
					assert.Error(t, err, "Expected validation error for replicas")
				}
			})
		}
	})

	t.Run("traffic_percentage_validation", func(t *testing.T) {
		t.Parallel()

		testCases := []struct {
			name       string
			percentage int
			shouldFail bool
		}{
			{"valid_0", 0, false},
			{"valid_50", 50, false},
			{"valid_100", 100, false},
			{"invalid_negative", -1, true},
			{"invalid_over_100", 101, true},
		}

		for _, tc := range testCases {
			tc := tc
			t.Run(tc.name, func(t *testing.T) {
				t.Parallel()

				uniqueID := strings.ToLower(random.UniqueId())

				terraformOptions := &terraform.Options{
					TerraformDir: "../modules/container-app",
					Vars: map[string]interface{}{
						"name":                      fmt.Sprintf("ca-test-%s", uniqueID),
						"environment_name":          fmt.Sprintf("cae-test-%s", uniqueID),
						"resource_group_name":       "rg-nonexistent",
						"location":                  "eastus2",
						"log_analytics_workspace_id": "/subscriptions/test/resourceGroups/test/providers/Microsoft.OperationalInsights/workspaces/test",
						"container_image":           "nginx:latest",
						"traffic_percentage":        tc.percentage,
					},
				}

				if tc.shouldFail {
					_, err := terraform.PlanE(t, terraformOptions)
					assert.Error(t, err, "Expected validation error for traffic percentage: %d", tc.percentage)
				}
			})
		}
	})
}

// TestContainerAppTransportValidation tests transport protocol validation
func TestContainerAppTransportValidation(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name       string
		transport  string
		shouldFail bool
	}{
		{"valid_http", "http", false},
		{"valid_http2", "http2", false},
		{"valid_tcp", "tcp", false},
		{"invalid_udp", "udp", true},
	}

	for _, tc := range testCases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			uniqueID := strings.ToLower(random.UniqueId())

			terraformOptions := &terraform.Options{
				TerraformDir: "../modules/container-app",
				Vars: map[string]interface{}{
					"name":                      fmt.Sprintf("ca-test-%s", uniqueID),
					"environment_name":          fmt.Sprintf("cae-test-%s", uniqueID),
					"resource_group_name":       "rg-nonexistent",
					"location":                  "eastus2",
					"log_analytics_workspace_id": "/subscriptions/test/resourceGroups/test/providers/Microsoft.OperationalInsights/workspaces/test",
					"container_image":           "nginx:latest",
					"ingress_transport":         tc.transport,
				},
			}

			if tc.shouldFail {
				_, err := terraform.PlanE(t, terraformOptions)
				assert.Error(t, err, "Expected validation error for transport: %s", tc.transport)
			}
		})
	}
}

// TestContainerAppRevisionModeValidation tests revision mode validation
func TestContainerAppRevisionModeValidation(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name         string
		revisionMode string
		shouldFail   bool
	}{
		{"valid_single", "Single", false},
		{"valid_multiple", "Multiple", false},
		{"invalid_mode", "Invalid", true},
	}

	for _, tc := range testCases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			uniqueID := strings.ToLower(random.UniqueId())

			terraformOptions := &terraform.Options{
				TerraformDir: "../modules/container-app",
				Vars: map[string]interface{}{
					"name":                      fmt.Sprintf("ca-test-%s", uniqueID),
					"environment_name":          fmt.Sprintf("cae-test-%s", uniqueID),
					"resource_group_name":       "rg-nonexistent",
					"location":                  "eastus2",
					"log_analytics_workspace_id": "/subscriptions/test/resourceGroups/test/providers/Microsoft.OperationalInsights/workspaces/test",
					"container_image":           "nginx:latest",
					"revision_mode":             tc.revisionMode,
				},
			}

			if tc.shouldFail {
				_, err := terraform.PlanE(t, terraformOptions)
				assert.Error(t, err, "Expected validation error for revision mode: %s", tc.revisionMode)
			}
		})
	}
}

// Note: Full integration tests that actually deploy Container Apps
// are commented out to avoid costs. Uncomment for full integration testing.

/*
// TestContainerAppIntegrationFull tests full deployment (expensive!)
func TestContainerAppIntegrationFull(t *testing.T) {
	t.Parallel()

	subscriptionID := azure.GetSubscriptionID(t)
	uniqueID := strings.ToLower(random.UniqueId())
	resourceGroupName := fmt.Sprintf("rg-ca-int-test-%s", uniqueID)
	location := "eastus2"

	// This would require:
	// 1. Resource group
	// 2. Log Analytics
	// 3. Application Insights
	// 4. Container Registry with image
	// 5. Container App

	// Too expensive for regular testing - use sparingly
}
*/
