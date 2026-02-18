# Azure Container Registry Module

A Terraform module for creating and managing Azure Container Registry (ACR) with security best practices, diagnostic logging, and configurable SKU tiers.

## Features

- Admin user disabled (uses Managed Identity for authentication)
- Configurable SKU tiers (Basic, Standard, Premium)
- Optional retention policies for untagged manifests (Premium only)
- Optional content trust policies (Premium only)
- Diagnostic logging integration with Log Analytics
- Scope maps for token-based authentication

## Usage

### Basic Example (Development)

```hcl
module "container_registry" {
  source = "../../modules/container-registry"

  name                = "acrmyappdev"
  resource_group_name = "rg-myapp-dev"
  location            = "eastus2"

  sku = "Basic"

  tags = {
    Environment = "dev"
  }
}
```

### Production Example

```hcl
module "container_registry" {
  source = "../../modules/container-registry"

  name                = "acrmyappprod"
  resource_group_name = "rg-myapp-prod"
  location            = "eastus2"

  sku                          = "Premium"
  public_network_access_enabled = false
  retention_enabled            = true
  retention_days               = 30
  trust_policy_enabled         = true

  log_analytics_workspace_id = module.observability.log_analytics_workspace_id

  tags = {
    Environment = "production"
    Compliance  = "SOC2"
  }
}
```

## Requirements

| Name      | Version  |
| --------- | -------- |
| terraform | >= 1.5.0 |
| azurerm   | ~> 4.0 |

## Inputs

| Name                          | Description                                                         | Type          | Default   | Required |
| ----------------------------- | ------------------------------------------------------------------- | ------------- | --------- | :------: |
| name                          | Name of the container registry (5-50 chars, lowercase alphanumeric) | `string`      | n/a       |   yes    |
| resource_group_name           | Name of the resource group                                          | `string`      | n/a       |   yes    |
| location                      | Azure region                                                        | `string`      | n/a       |   yes    |
| sku                           | SKU tier (Basic, Standard, Premium)                                 | `string`      | `"Basic"` |    no    |
| public_network_access_enabled | Enable public network access                                        | `bool`        | `true`    |    no    |
| encryption_enabled            | Enable customer-managed key encryption (Premium only)               | `bool`        | `false`   |    no    |
| retention_enabled             | Enable retention policy for untagged manifests                      | `bool`        | `false`   |    no    |
| retention_days                | Days to retain untagged manifests (0-365)                           | `number`      | `7`       |    no    |
| trust_policy_enabled          | Enable content trust (Premium only)                                 | `bool`        | `false`   |    no    |
| create_scope_maps             | Create scope maps for token auth                                    | `bool`        | `false`   |    no    |
| enable_diagnostics            | Enable diagnostic settings                                          | `bool`        | `true`    |    no    |
| log_analytics_workspace_id    | Log Analytics workspace ID (required if enable_diagnostics = true)  | `string`      | `""`      |    no    |
| tags                          | Tags to apply                                                       | `map(string)` | `{}`      |    no    |

### Validation Rules

- **name**: Must be 5-50 characters, lowercase alphanumeric only
- **sku**: Must be `Basic`, `Standard`, or `Premium`
- **retention_days**: Must be between 0 and 365

## Outputs

| Name           | Description                                   |
| -------------- | --------------------------------------------- |
| id             | The ID of the container registry              |
| name           | The name of the container registry            |
| login_server   | The URL for logging into the registry         |
| admin_username | Admin username (always null - admin disabled) |
| admin_password | Admin password (always null - admin disabled) |
| identity       | The identity block of the registry            |

## SKU Comparison

| Feature              | Basic | Standard | Premium |
| -------------------- | ----- | -------- | ------- |
| Included storage     | 10 GB | 100 GB   | 500 GB  |
| Max bandwidth        | N/A   | N/A      | N/A     |
| Geo-replication      | No    | No       | Yes     |
| Content trust        | No    | No       | Yes     |
| Private endpoints    | No    | No       | Yes     |
| Retention policies   | No    | No       | Yes     |
| Zone redundancy      | No    | No       | Yes     |
| Estimated cost/month | ~$5   | ~$20     | ~$50    |

## Security Best Practices

1. **Admin user is disabled** - Use Managed Identity for authentication
2. **Use Premium SKU for production** - Enables private endpoints and geo-replication
3. **Enable retention policies** - Clean up untagged images automatically
4. **Disable public access** - Use private endpoints in production
5. **Enable diagnostic logging** - Monitor all registry access

## Examples

- [Complete Example](./examples/complete/) - Full usage example with all options

## Contributing

1. Follow the existing code structure
2. Update tests for new functionality
3. Update documentation for any changes

## License

MIT License - See [LICENSE](../../../LICENSE) for details.
