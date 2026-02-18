# Azure Observability Module

A Terraform module for creating a complete observability stack with Log Analytics Workspace and Application Insights, including optional availability testing.

## Features

- Workspace-based Application Insights (modern approach)
- Configurable data retention and daily caps
- Optional availability web tests for health endpoints
- IP masking options for debugging vs. privacy
- Local authentication control for AAD/RBAC
- Private link support for production

## Usage

### Basic Example (Development)

```hcl
module "observability" {
  source = "../../modules/observability"

  resource_group_name = "rg-myapp-dev"
  location            = "eastus2"

  log_analytics_name = "log-myapp-dev"
  app_insights_name  = "appi-myapp-dev"

  tags = {
    Environment = "dev"
  }
}
```

### Production Example

```hcl
module "observability" {
  source = "../../modules/observability"

  resource_group_name           = "rg-myapp-prod"
  location                      = "eastus2"

  # Log Analytics Configuration
  log_analytics_name            = "log-myapp-prod"
  log_analytics_sku             = "PerGB2018"
  log_analytics_retention_days  = 90
  log_analytics_daily_quota_gb  = 10

  # Application Insights Configuration
  app_insights_name             = "appi-myapp-prod"
  application_type              = "web"
  sampling_percentage           = 30  # Sample 30% in production
  app_insights_daily_cap_gb     = 5

  # Security settings
  disable_ip_masking            = false
  local_authentication_disabled = true
  internet_ingestion_enabled    = false
  internet_query_enabled        = false

  # Availability test
  create_availability_test      = true
  health_check_url              = "https://myapp.azurecontainerapps.io/health"
  test_locations = [
    "us-va-ash-azr",  # US East
    "us-ca-sjc-azr",  # US West
    "emea-nl-ams-azr" # Europe
  ]

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

### Common Variables

| Name                | Description                | Type          | Default | Required |
| ------------------- | -------------------------- | ------------- | ------- | :------: |
| resource_group_name | Name of the resource group | `string`      | n/a     |   yes    |
| location            | Azure region               | `string`      | n/a     |   yes    |
| tags                | Tags to apply              | `map(string)` | `{}`    |    no    |

### Log Analytics Variables

| Name                         | Description                              | Type     | Default       | Required |
| ---------------------------- | ---------------------------------------- | -------- | ------------- | :------: |
| log_analytics_name           | Name of the Log Analytics workspace      | `string` | n/a           |   yes    |
| log_analytics_sku            | SKU (PerGB2018 or Free)                  | `string` | `"PerGB2018"` |    no    |
| log_analytics_retention_days | Data retention (7-730 days)              | `number` | `30`          |    no    |
| log_analytics_daily_quota_gb | Daily ingestion quota (null = unlimited) | `number` | `null`        |    no    |

### Application Insights Variables

| Name                          | Description                                   | Type     | Default | Required |
| ----------------------------- | --------------------------------------------- | -------- | ------- | :------: |
| app_insights_name             | Name of the Application Insights instance     | `string` | n/a     |   yes    |
| application_type              | Application type (web, other, java, Node.JS)  | `string` | `"web"` |    no    |
| sampling_percentage           | Telemetry sampling percentage (1-100)         | `number` | `100`   |    no    |
| app_insights_retention_days   | Data retention (null = use workspace default) | `number` | `null`  |    no    |
| app_insights_daily_cap_gb     | Daily data cap (null = unlimited)             | `number` | `null`  |    no    |
| disable_ip_masking            | Show full IPs for debugging                   | `bool`   | `true`  |    no    |
| local_authentication_disabled | Disable local auth (use AAD)                  | `bool`   | `false` |    no    |
| internet_ingestion_enabled    | Enable internet ingestion                     | `bool`   | `true`  |    no    |
| internet_query_enabled        | Enable internet query access                  | `bool`   | `true`  |    no    |

### Availability Test Variables

| Name                     | Description                   | Type           | Default                              | Required |
| ------------------------ | ----------------------------- | -------------- | ------------------------------------ | :------: |
| create_availability_test | Create availability web test  | `bool`         | `false`                              |    no    |
| health_check_url         | URL for health check          | `string`       | `null`                               |    no    |
| test_locations           | Azure regions for tests       | `list(string)` | `["us-va-ash-azr", "us-ca-sjc-azr"]` |    no    |
| health_check_headers     | HTTP headers for health check | `map(string)`  | `{}`                                 |    no    |

## Outputs

### Log Analytics Outputs

| Name                                 | Description                             |
| ------------------------------------ | --------------------------------------- |
| log_analytics_workspace_id           | The ID of the Log Analytics workspace   |
| log_analytics_workspace_name         | The name of the Log Analytics workspace |
| log_analytics_primary_shared_key     | The primary shared key (sensitive)      |
| log_analytics_workspace_id_for_query | The workspace ID for queries            |

### Application Insights Outputs

| Name                             | Description                                   |
| -------------------------------- | --------------------------------------------- |
| app_insights_id                  | The ID of the Application Insights instance   |
| app_insights_name                | The name of the Application Insights instance |
| app_insights_instrumentation_key | The instrumentation key (sensitive)           |
| app_insights_connection_string   | The connection string (sensitive)             |
| app_insights_app_id              | The app ID                                    |

## Application Types

| Type    | Use Case                                   |
| ------- | ------------------------------------------ |
| web     | Web applications (React, Angular, FastAPI) |
| other   | Generic applications                       |
| java    | Java applications                          |
| Node.JS | Node.js applications                       |

## Test Locations

Common availability test locations:

| Code            | Location                 |
| --------------- | ------------------------ |
| us-va-ash-azr   | US East (Virginia)       |
| us-ca-sjc-azr   | US West (California)     |
| us-tx-sn1-azr   | US South Central (Texas) |
| emea-nl-ams-azr | Europe (Netherlands)     |
| emea-gb-db3-azr | Europe (UK)              |
| apac-jp-kaw-azr | Asia Pacific (Japan)     |
| apac-sg-sin-azr | Asia Pacific (Singapore) |

## Cost Optimization

| Environment | Sampling | Daily Cap | Retention |
| ----------- | -------- | --------- | --------- |
| Development | 100%     | 2-5 GB    | 30 days   |
| Staging     | 50%      | 5 GB      | 30 days   |
| Production  | 20-30%   | 10-20 GB  | 90 days   |

## Security Best Practices

1. **Disable IP masking in production** - Privacy compliance
2. **Disable local authentication** - Use AAD/RBAC
3. **Disable internet access with Private Link** - Network isolation
4. **Set daily caps** - Prevent cost overruns
5. **Use appropriate sampling** - Balance cost and coverage

## Examples

- [Complete Example](./examples/complete/) - Full usage example with all options

## Contributing

1. Follow the existing code structure
2. Update tests for new functionality
3. Update documentation for any changes

## License

MIT License - See [LICENSE](../../../LICENSE) for details.
