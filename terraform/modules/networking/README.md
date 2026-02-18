# Networking Module

Creates a Virtual Network with subnets for private endpoints and Container App environment VNet injection.

## Resources

| Resource | Purpose |
|----------|---------|
| `azurerm_virtual_network` | Main VNet |
| `azurerm_subnet.private_endpoints` | Subnet for Key Vault and ACR private endpoints |
| `azurerm_subnet.container_app` | Delegated subnet for Container App environment |

## Architecture

```
VNet: 10.0.0.0/16
├── snet-private-endpoints (10.0.1.0/24)
│   └── Private endpoints for Key Vault, ACR
└── snet-container-app (10.0.2.0/23)
    └── Container App Environment (VNet injected)
```

## Usage

```hcl
module "networking" {
  source = "../../modules/networking"

  vnet_name           = "vnet-finrisk-dev"
  resource_group_name = "rg-finrisk-dev"
  location            = "eastus2"

  # Optional: customize address spaces
  vnet_address_space           = "10.0.0.0/16"
  private_endpoint_subnet_cidr = "10.0.1.0/24"
  container_app_subnet_cidr    = "10.0.2.0/23"

  tags = { Environment = "dev" }
}
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `vnet_name` | Name of the Virtual Network | `string` | Required |
| `resource_group_name` | Resource group name | `string` | Required |
| `location` | Azure region | `string` | Required |
| `vnet_address_space` | VNet CIDR | `string` | `"10.0.0.0/16"` |
| `private_endpoint_subnet_cidr` | Private endpoints subnet CIDR | `string` | `"10.0.1.0/24"` |
| `container_app_subnet_cidr` | Container App subnet CIDR | `string` | `"10.0.2.0/23"` |
| `tags` | Resource tags | `map(string)` | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| `vnet_id` | Resource ID of the VNet |
| `vnet_name` | Name of the VNet |
| `private_endpoint_subnet_id` | Subnet ID for private endpoints |
| `container_app_subnet_id` | Subnet ID for Container App environment |

## Requirements

| Name | Version |
|------|---------|
| Terraform | >= 1.5.0 |
| azurerm | ~> 3.100 |

## Notes

- The Container App subnet must be `/23` or larger (Azure requirement)
- `private_endpoint_network_policies_enabled = false` is required for the private endpoints subnet
- The Container App subnet is delegated to `Microsoft.App/environments`
