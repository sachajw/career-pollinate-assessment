# Private Endpoints Module

Creates private endpoints for Key Vault and Azure Container Registry with Private DNS zones, routing all traffic over the VNet.

## Resources

| Resource                                                 | Purpose                                  |
| -------------------------------------------------------- | ---------------------------------------- |
| `azurerm_private_dns_zone.keyvault`                      | DNS zone for Key Vault private endpoints |
| `azurerm_private_dns_zone_virtual_network_link.keyvault` | Links Key Vault DNS zone to VNet         |
| `azurerm_private_endpoint.keyvault`                      | Private endpoint for Key Vault           |
| `azurerm_private_dns_zone.acr`                           | DNS zone for ACR private endpoints       |
| `azurerm_private_dns_zone_virtual_network_link.acr`      | Links ACR DNS zone to VNet               |
| `azurerm_private_endpoint.acr`                           | Private endpoint for ACR                 |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        VNet                                      │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Private Endpoints Subnet                                   │  │
│  │                                                            │  │
│  │  ┌─────────────────┐      ┌─────────────────┐            │  │
│  │  │ Key Vault PE    │      │ ACR PE          │            │  │
│  │  │ 10.0.1.x        │      │ 10.0.1.y        │            │  │
│  │  └────────┬────────┘      └────────┬────────┘            │  │
│  │           │                        │                      │  │
│  └───────────┼────────────────────────┼──────────────────────┘  │
│              │                        │                          │
│  ┌───────────┴────────────────────────┴──────────────────────┐  │
│  │ Private DNS Zones                                          │  │
│  │  • privatelink.vaultcore.azure.net → Key Vault PE IP      │  │
│  │  • privatelink.azurecr.io        → ACR PE IPs             │  │
│  └────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Usage

```hcl
module "private_endpoints" {
  source = "../../modules/private-endpoints"

  resource_group_name        = "rg-finrisk-dev"
  location                   = "eastus2"
  environment                = "dev"
  vnet_id                    = module.networking.vnet_id
  private_endpoint_subnet_id = module.networking.private_endpoint_subnet_id
  key_vault_id               = module.key_vault.id
  container_registry_id      = module.container_registry.id

  tags = { Environment = "dev" }

  depends_on = [
    module.networking,
    module.key_vault,
    module.container_registry,
  ]
}
```

## Inputs

| Name                         | Description                        | Type          | Default  |
| ---------------------------- | ---------------------------------- | ------------- | -------- |
| `resource_group_name`        | Resource group name                | `string`      | Required |
| `location`                   | Azure region                       | `string`      | Required |
| `environment`                | Environment name (used for naming) | `string`      | Required |
| `vnet_id`                    | VNet resource ID                   | `string`      | Required |
| `private_endpoint_subnet_id` | Subnet ID for private endpoints    | `string`      | Required |
| `key_vault_id`               | Key Vault resource ID              | `string`      | Required |
| `container_registry_id`      | ACR resource ID                    | `string`      | Required |
| `tags`                       | Resource tags                      | `map(string)` | `{}`     |

## Outputs

| Name                                     | Description                       |
| ---------------------------------------- | --------------------------------- |
| `key_vault_private_endpoint_id`          | Private endpoint ID for Key Vault |
| `key_vault_private_ip`                   | Private IP for Key Vault endpoint |
| `container_registry_private_endpoint_id` | Private endpoint ID for ACR       |
| `container_registry_private_ip`          | Private IP for ACR endpoint       |

## Requirements

| Name      | Version  |
| --------- | -------- |
| Terraform | >= 1.5.0 |
| azurerm   | ~> 4.0   |

## Prerequisites

1. **VNet** with private endpoints subnet (`private_endpoint_network_policies = "Disabled"`)
2. **Key Vault** with `public_network_access_enabled = false`
3. **ACR** with `public_network_access_enabled = false` and SKU >= Standard

## Important: Pipeline Agent Connectivity

When private endpoints are enabled, your CI/CD pipeline agent must have VNet connectivity to:

- Pull images from ACR
- Read secrets from Key Vault
- Run Terraform operations

**Options:**

1. Point-to-Site VPN Gateway (~$30/mo)
2. Self-hosted agent on VM inside VNet (~$30-50/mo)
3. Azure DevOps managed agents with VNet injection

## Verification

```bash
# From inside VNet - should resolve to private IP
nslookup kv-finrisk-dev.vault.azure.net
# Expected: 10.0.1.x

nslookup acrfinriskdev.azurecr.io
# Expected: 10.0.1.y
```

## Cost Impact

| Resource              | Monthly Cost |
| --------------------- | ------------ |
| Private Endpoints (2) | ~$14/mo      |
| Private DNS Zones (2) | ~$1/mo       |
| **Total**             | **~$15/mo**  |

Note: ACR must be Standard SKU (additional ~$20/mo vs Basic)
