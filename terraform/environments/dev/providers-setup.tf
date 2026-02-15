#------------------------------------------------------------------------------
# Azure Resource Provider Registration
#------------------------------------------------------------------------------
# Ensures all required providers are registered before infrastructure deployment
# Prevents "MissingSubscriptionRegistration" errors during apply
#
# NOTE: Provider registration is subscription-level and idempotent
# If already registered, this will complete instantly
#------------------------------------------------------------------------------

resource "azurerm_resource_provider_registration" "container_apps" {
  name = "Microsoft.App"
}

resource "azurerm_resource_provider_registration" "container_registry" {
  name = "Microsoft.ContainerRegistry"
}

resource "azurerm_resource_provider_registration" "key_vault" {
  name = "Microsoft.KeyVault"
}

resource "azurerm_resource_provider_registration" "operational_insights" {
  name = "Microsoft.OperationalInsights"
}

resource "azurerm_resource_provider_registration" "insights" {
  name = "Microsoft.Insights"
}

resource "azurerm_resource_provider_registration" "storage" {
  name = "Microsoft.Storage"
}

#------------------------------------------------------------------------------
# Wait for Provider Registration
#------------------------------------------------------------------------------
# Azure provider registration can take 30-60 seconds
# Wait to ensure providers are fully available before creating resources
#------------------------------------------------------------------------------
resource "time_sleep" "wait_for_providers" {
  depends_on = [
    azurerm_resource_provider_registration.container_apps,
    azurerm_resource_provider_registration.container_registry,
    azurerm_resource_provider_registration.key_vault,
    azurerm_resource_provider_registration.operational_insights,
    azurerm_resource_provider_registration.insights,
    azurerm_resource_provider_registration.storage,
  ]

  create_duration = "60s"

  triggers = {
    # Force recreation if providers change
    providers = join(",", [
      azurerm_resource_provider_registration.container_apps.name,
      azurerm_resource_provider_registration.container_registry.name,
      azurerm_resource_provider_registration.key_vault.name,
      azurerm_resource_provider_registration.operational_insights.name,
      azurerm_resource_provider_registration.insights.name,
      azurerm_resource_provider_registration.storage.name,
    ])
  }
}
