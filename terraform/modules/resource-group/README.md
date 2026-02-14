# Azure Resource Group Module

A Terraform module for creating and managing Azure Resource Groups with input validation and tagging support.

## Features

- Input validation for naming convention (must start with `rg-`)
- Region restriction to approved Azure regions
- Configurable tags for resource organization

## Usage

### Basic Example

```hcl
module "resource_group" {
  source = "../../modules/resource-group"

  name     = "rg-myapp-dev"
  location = "eastus2"

  tags = {
    Environment = "dev"
    Project     = "myapp"
    ManagedBy   = "terraform"
  }
}
```

### Production Example

```hcl
module "resource_group" {
  source = "../../modules/resource-group"

  name     = "rg-myapp-prod"
  location = "westus2"

  tags = {
    Environment = "production"
    Project     = "myapp"
    ManagedBy   = "terraform"
    CostCenter  = "engineering"
    Compliance  = "SOC2"
  }
}
```

## Requirements

| Name      | Version  |
| --------- | -------- |
| terraform | >= 1.5.0 |
| azurerm   | ~> 3.100 |

## Inputs

| Name     | Description                                        | Type          | Default | Required |
| -------- | -------------------------------------------------- | ------------- | ------- | :------: |
| name     | Name of the resource group (must start with 'rg-') | `string`      | n/a     |   yes    |
| location | Azure region for the resource group                | `string`      | n/a     |   yes    |
| tags     | Tags to apply to the resource group                | `map(string)` | `{}`    |    no    |

### Validation Rules

- **name**: Must start with `rg-` prefix
- **location**: Must be one of `eastus2`, `westus2`, or `centralus`

## Outputs

| Name     | Description                            |
| -------- | -------------------------------------- |
| id       | The ID of the resource group           |
| name     | The name of the resource group         |
| location | The Azure region of the resource group |

## Examples

- [Complete Example](./examples/complete/) - Full usage example with all options

## Contributing

1. Follow the existing code structure
2. Update tests for new functionality
3. Update documentation for any changes

## License

MIT License - See [LICENSE](../../../LICENSE) for details.
