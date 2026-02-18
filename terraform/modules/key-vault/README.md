# Azure Key Vault Module

A Terraform module for creating and managing Azure Key Vault with RBAC authorization, soft delete protection, network security, and diagnostic logging.

## Features

- RBAC-based access control (modern approach, not legacy access policies)
- Soft delete and purge protection enabled by default
- Network ACLs support for production security
- Optional private endpoint support
- Diagnostic logging integration with Log Analytics
- Initial secrets injection via variable (use with caution)
- Lifecycle preconditions for configuration validation

## Usage

### Basic Example (Development)

```hcl
module "key_vault" {
  source = "../../modules/key-vault"

  name                = "kv-myapp-dev"
  resource_group_name = "rg-myapp-dev"
  location            = "eastus2"

  sku_name = "standard"

  tags = {
    Environment = "dev"
  }
}
```

### Production Example with Network Security

```hcl
module "key_vault" {
  source = "../../modules/key-vault"

  name                = "kv-myapp-prod"
  resource_group_name = "rg-myapp-prod"
  location            = "eastus2"

  sku_name                     = "premium"
  soft_delete_retention_days   = 90
  purge_protection_enabled     = true
  public_network_access_enabled = false

  network_acls_enabled         = true
  network_acls_default_action  = "Deny"
  network_acls_bypass          = "AzureServices"
  allowed_subnet_ids           = [module.vnet.private_subnet_id]

  deployer_object_id           = data.azurerm_client_config.current.object_id
  log_analytics_workspace_id   = module.observability.log_analytics_workspace_id

  tags = {
    Environment = "production"
    Compliance  = "SOC2"
  }
}
```

### With Initial Secrets

```hcl
module "key_vault" {
  source = "../../modules/key-vault"

  name                = "kv-myapp-dev"
  resource_group_name = "rg-myapp-dev"
  location            = "eastus2"

  deployer_object_id = data.azurerm_client_config.current.object_id

  # WARNING: Prefer external secret injection via CI/CD
  secrets = {
    "DB-CONNECTION-STRING" = "Server=tcp:..."
  }

  tags = {
    Environment = "dev"
  }
}
```

## Requirements

| Name      | Version  |
| --------- | -------- |
| terraform | >= 1.5.0 |
| azurerm   | ~> 4.0 |

## Inputs

| Name                          | Description                                                        | Type           | Default           | Required |
| ----------------------------- | ------------------------------------------------------------------ | -------------- | ----------------- | :------: |
| name                          | Name of the Key Vault (3-24 chars, globally unique)                | `string`       | n/a               |   yes    |
| resource_group_name           | Name of the resource group                                         | `string`       | n/a               |   yes    |
| location                      | Azure region                                                       | `string`       | n/a               |   yes    |
| sku_name                      | SKU (standard or premium)                                          | `string`       | `"standard"`      |    no    |
| soft_delete_retention_days    | Days to retain deleted items (7-90)                                | `number`       | `90`              |    no    |
| purge_protection_enabled      | Prevent permanent deletion during retention                        | `bool`         | `true`            |    no    |
| public_network_access_enabled | Enable public network access                                       | `bool`         | `true`            |    no    |
| network_acls_enabled          | Enable network ACLs                                                | `bool`         | `false`           |    no    |
| network_acls_bypass           | Traffic bypass (AzureServices or None)                             | `string`       | `"AzureServices"` |    no    |
| network_acls_default_action   | Default ACL action (Allow or Deny)                                 | `string`       | `"Deny"`          |    no    |
| allowed_ip_ranges             | List of allowed IP ranges                                          | `list(string)` | `[]`              |    no    |
| allowed_subnet_ids            | List of allowed subnet IDs                                         | `list(string)` | `[]`              |    no    |
| deployer_object_id            | Object ID for RBAC assignment                                      | `string`       | `null`            |    no    |
| enable_diagnostics            | Enable diagnostic settings                                         | `bool`         | `true`            |    no    |
| log_analytics_workspace_id    | Log Analytics workspace ID (required if enable_diagnostics = true) | `string`       | `""`              |    no    |
| secrets                       | Map of secrets to create (not marked sensitive to allow for_each)  | `map(string)`  | `{}`              |    no    |
| tags                          | Tags to apply                                                      | `map(string)`  | `{}`              |    no    |

### Validation Rules

- **name**: Must be 3-24 characters, start with letter, alphanumeric and hyphens only
- **sku_name**: Must be `standard` or `premium`
- **soft_delete_retention_days**: Must be between 7 and 90

## Outputs

| Name        | Description                   |
| ----------- | ----------------------------- |
| id          | The ID of the Key Vault       |
| name        | The name of the Key Vault     |
| vault_uri   | The URI of the Key Vault      |
| tenant_id   | The Azure AD tenant ID        |
| resource_id | The Azure Resource Manager ID |

## SKU Comparison

| Feature              | Standard         | Premium           |
| -------------------- | ---------------- | ----------------- |
| Secrets              | Unlimited        | Unlimited         |
| Keys                 | Unlimited        | Unlimited         |
| Certificates         | Unlimited        | Unlimited         |
| HSM-backed keys      | No               | Yes               |
| Private endpoints    | Yes              | Yes               |
| Estimated cost/month | ~$3 + operations | ~$15 + operations |

## Security Best Practices

1. **Always enable soft delete** - Prevents accidental data loss
2. **Enable purge protection** - Prevents permanent deletion during retention
3. **Use RBAC authorization** - More granular than access policies
4. **Restrict network access** - Use private endpoints in production
5. **Enable diagnostic logging** - Required for SOC 2 compliance
6. **Avoid secrets in Terraform** - Prefer external secret injection via CI/CD

## RBAC Roles

The module assigns `Key Vault Administrator` to the deployer. For production:

| Role                      | Use Case                    |
| ------------------------- | --------------------------- |
| Key Vault Administrator   | Full management (deployers) |
| Key Vault Secrets User    | Read secrets (applications) |
| Key Vault Secrets Officer | Manage secrets (CI/CD)      |
| Key Vault Crypto User     | Read keys                   |
| Key Vault Crypto Officer  | Manage keys                 |

## Examples

- [Complete Example](./examples/complete/) - Full usage example with all options

## Contributing

1. Follow the existing code structure
2. Update tests for new functionality
3. Update documentation for any changes

## License

MIT License - See [LICENSE](../../../LICENSE) for details.
