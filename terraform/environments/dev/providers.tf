# Azure Provider Configuration
provider "azurerm" {
  features {
    key_vault {
      # Don't purge soft-deleted items on destroy
      purge_soft_delete_on_destroy               = false
      purge_soft_deleted_keys_on_destroy         = false
      purge_soft_deleted_secrets_on_destroy      = false
      purge_soft_deleted_certificates_on_destroy = false
    }

    resource_group {
      # Don't force delete resources on destroy
      prevent_deletion_if_contains_resources = true
    }
  }
}
