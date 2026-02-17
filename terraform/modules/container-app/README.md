# Azure Container App Module

A Terraform module for creating Azure Container Apps with managed identity, autoscaling, health probes, ingress configuration, and integrated RBAC for ACR and Key Vault access.

## Features

- System-assigned managed identity for Azure service authentication
- HTTP-based and custom autoscaling rules
- Startup, liveness, and readiness health probes
- HTTPS-only ingress (CORS handled at application level, not infra)
- Blue/green deployment support via traffic weighting
- IP security restrictions
- Dapr sidecar support (optional)
- Automatic RBAC assignments for ACR and Key Vault
- VNet integration and private ingress support

## Usage

### Basic Example (Development)

```hcl
module "container_app" {
  source = "../../modules/container-app"

  name                = "ca-myapp-dev"
  environment_name    = "cae-myapp-dev"
  resource_group_name = "rg-myapp-dev"
  location            = "eastus2"

  log_analytics_workspace_id = module.observability.log_analytics_workspace_id

  container_name  = "api"
  container_image = "myapp/api:latest"
  container_cpu   = 0.5
  container_memory = "1Gi"

  min_replicas = 0  # Scale to zero
  max_replicas = 3

  ingress_enabled      = true
  ingress_target_port  = 8080

  tags = {
    Environment = "dev"
  }
}
```

### Production Example

```hcl
module "container_app" {
  source = "../../modules/container-app"

  name                = "ca-myapp-prod"
  environment_name    = "cae-myapp-prod"
  resource_group_name = "rg-myapp-prod"
  location            = "eastus2"

  log_analytics_workspace_id    = module.observability.log_analytics_workspace_id
  infrastructure_subnet_id      = module.vnet.container_apps_subnet_id
  internal_load_balancer_enabled = false
  zone_redundancy_enabled       = true

  # Container configuration
  container_name   = "api"
  container_image  = "${module.container_registry.login_server}/myapp/api:v1.2.3"
  container_cpu    = 1.0
  container_memory = "2Gi"

  # Scaling
  min_replicas = 2
  max_replicas = 20
  http_scale_rule_enabled        = true
  http_scale_concurrent_requests = 50

  # Environment variables
  environment_variables = {
    ENVIRONMENT = "production"
    LOG_LEVEL   = "INFO"
  }

  # Health probes
  liveness_probe_enabled  = true
  liveness_probe_path     = "/health"
  liveness_probe_port     = 8080

  readiness_probe_enabled  = true
  readiness_probe_path     = "/ready"
  readiness_probe_port     = 8080

  # Ingress
  ingress_enabled            = true
  ingress_external_enabled   = true
  ingress_target_port        = 8080
  allow_insecure_connections = false

  # NOTE: CORS should be handled at the application level (e.g., FastAPI middleware)
  # The azurerm_container_app resource does not support CORS configuration in ingress

  # Registry and secrets
  registry_server        = module.container_registry.login_server
  enable_acr_pull        = true
  container_registry_id  = module.container_registry.id

  enable_key_vault_access = true
  key_vault_id            = module.key_vault.id

  tags = {
    Environment = "production"
    Compliance  = "SOC2"
  }

  depends_on = [
    module.observability,
    module.container_registry,
    module.key_vault
  ]
}
```

## Requirements

| Name      | Version  |
| --------- | -------- |
| terraform | >= 1.5.0 |
| azurerm   | ~> 3.100 |

## Inputs

### Common Variables

| Name                | Description                           | Type          | Default | Required |
| ------------------- | ------------------------------------- | ------------- | ------- | :------: |
| name                | Name of the container app             | `string`      | n/a     |   yes    |
| environment_name    | Name of the container app environment | `string`      | n/a     |   yes    |
| resource_group_name | Name of the resource group            | `string`      | n/a     |   yes    |
| location            | Azure region                          | `string`      | n/a     |   yes    |
| tags                | Tags to apply                         | `map(string)` | `{}`    |    no    |

### Environment Configuration

| Name                           | Description                    | Type     | Default | Required |
| ------------------------------ | ------------------------------ | -------- | ------- | :------: |
| log_analytics_workspace_id     | Log Analytics workspace ID     | `string` | n/a     |   yes    |
| infrastructure_subnet_id       | Subnet ID for VNet integration | `string` | `null`  |    no    |
| internal_load_balancer_enabled | Enable private ingress         | `bool`   | `false` |    no    |
| zone_redundancy_enabled        | Enable zone redundancy         | `bool`   | `false` |    no    |

### Container Configuration

| Name                         | Description                            | Type          | Default    | Required |
| ---------------------------- | -------------------------------------- | ------------- | ---------- | :------: |
| revision_mode                | Revision mode (Single or Multiple)     | `string`      | `"Single"` |    no    |
| container_name               | Name of the container                  | `string`      | `"api"`    |    no    |
| container_image              | Full container image path              | `string`      | n/a        |   yes    |
| container_cpu                | CPU allocation (0.25-2.0)              | `number`      | `0.5`      |    no    |
| container_memory             | Memory allocation                      | `string`      | `"1Gi"`    |    no    |
| environment_variables        | Non-sensitive environment variables    | `map(string)` | `{}`       |    no    |
| secret_environment_variables | Secret environment variable references | `map(string)` | `{}`       |    no    |
| secrets                      | Secrets to store in Container App      | `map(string)` | `{}`       |    no    |

### Scaling Configuration

| Name                           | Description                            | Type           | Default | Required |
| ------------------------------ | -------------------------------------- | -------------- | ------- | :------: |
| min_replicas                   | Minimum replicas (0 for scale-to-zero) | `number`       | `1`     |    no    |
| max_replicas                   | Maximum replicas                       | `number`       | `10`    |    no    |
| http_scale_rule_enabled        | Enable HTTP autoscaling                | `bool`         | `true`  |    no    |
| http_scale_concurrent_requests | Concurrent requests before scaling     | `number`       | `100`   |    no    |
| custom_scale_rules             | Custom scale rules                     | `list(object)` | `[]`    |    no    |

### Health Probes

| Name                    | Description            | Type     | Default     | Required |
| ----------------------- | ---------------------- | -------- | ----------- | :------: |
| startup_probe_enabled   | Enable startup probe   | `bool`   | `false`     |    no    |
| startup_probe_path      | Startup probe path     | `string` | `"/health"` |    no    |
| startup_probe_port      | Startup probe port     | `number` | `8080`      |    no    |
| liveness_probe_enabled  | Enable liveness probe  | `bool`   | `true`      |    no    |
| liveness_probe_path     | Liveness probe path    | `string` | `"/health"` |    no    |
| liveness_probe_port     | Liveness probe port    | `number` | `8080`      |    no    |
| readiness_probe_enabled | Enable readiness probe | `bool`   | `true`      |    no    |
| readiness_probe_path    | Readiness probe path   | `string` | `"/ready"`  |    no    |
| readiness_probe_port    | Readiness probe port   | `number` | `8080`      |    no    |

### Ingress Configuration

| Name                       | Description                      | Type     | Default  | Required |
| -------------------------- | -------------------------------- | -------- | -------- | :------: |
| ingress_enabled            | Enable ingress                   | `bool`   | `true`   |    no    |
| ingress_external_enabled   | Enable external (public) ingress | `bool`   | `true`   |    no    |
| ingress_target_port        | Target port                      | `number` | `8080`   |    no    |
| ingress_transport          | Transport protocol               | `string` | `"http"` |    no    |
| allow_insecure_connections | Allow HTTP (not just HTTPS)      | `bool`   | `false`  |    no    |
| traffic_latest_revision    | Route to latest revision         | `bool`   | `true`   |    no    |
| traffic_percentage         | Traffic percentage               | `number` | `100`    |    no    |

> **Note:** CORS is not supported at the infrastructure level in Azure Container Apps. Configure CORS in your application code (e.g., FastAPI CORS middleware).

### Registry and Key Vault

| Name                    | Description                                                        | Type     | Default | Required |
| ----------------------- | ------------------------------------------------------------------ | -------- | ------- | :------: |
| registry_server         | Container registry server                                          | `string` | `""`    |    no    |
| enable_acr_pull         | Enable ACR pull role assignment                                    | `bool`   | `false` |    no    |
| container_registry_id   | ACR ID for RBAC (required if enable_acr_pull = true)               | `string` | `""`    |    no    |
| enable_key_vault_access | Enable Key Vault secrets user role assignment                      | `bool`   | `false` |    no    |
| key_vault_id            | Key Vault ID for RBAC (required if enable_key_vault_access = true) | `string` | `""`    |    no    |

### Dapr Configuration

| Name              | Description           | Type     | Default  | Required |
| ----------------- | --------------------- | -------- | -------- | :------: |
| dapr_enabled      | Enable Dapr sidecar   | `bool`   | `false`  |    no    |
| dapr_app_id       | Dapr application ID   | `string` | `null`   |    no    |
| dapr_app_protocol | Dapr protocol         | `string` | `"http"` |    no    |
| dapr_app_port     | Dapr application port | `number` | `null`   |    no    |

## Outputs

### Environment Outputs

| Name                       | Description                               |
| -------------------------- | ----------------------------------------- |
| environment_id             | The ID of the container app environment   |
| environment_name           | The name of the container app environment |
| environment_default_domain | The default domain                        |
| environment_static_ip      | The static IP address                     |

### Container App Outputs

| Name                  | Description                     |
| --------------------- | ------------------------------- |
| id                    | The ID of the container app     |
| name                  | The name of the container app   |
| latest_revision_name  | The name of the latest revision |
| latest_revision_fqdn  | The FQDN of the latest revision |
| outbound_ip_addresses | List of outbound IP addresses   |

### Identity Outputs

| Name                  | Description                              |
| --------------------- | ---------------------------------------- |
| identity_principal_id | The principal ID of the managed identity |
| identity_tenant_id    | The tenant ID of the managed identity    |

### Ingress Outputs

| Name            | Description                           |
| --------------- | ------------------------------------- |
| ingress_fqdn    | The FQDN of the ingress               |
| application_url | The full HTTPS URL of the application |

### Custom Domain Outputs

| Name                          | Description                                              |
| ----------------------------- | -------------------------------------------------------- |
| custom_domain_verification_id | Domain verification ID for custom domain ownership proof |
| certificate_id                | ID of the referenced certificate (null if not enabled)   |

## Resource Sizing

| CPU  | Memory | Use Case                   |
| ---- | ------ | -------------------------- |
| 0.25 | 0.5Gi  | Development, low traffic   |
| 0.5  | 1Gi    | Standard workloads         |
| 1.0  | 2Gi    | CPU-intensive workloads    |
| 2.0  | 4Gi    | High-performance workloads |

## RBAC Assignments

When `container_registry_id` is provided:

- Assigns `AcrPull` role to the container app's managed identity

When `key_vault_id` is provided:

- Assigns `Key Vault Secrets User` role to the container app's managed identity

## Health Probe Configuration

| Probe Type | Purpose                                | Default Path |
| ---------- | -------------------------------------- | ------------ |
| Startup    | Wait for container startup             | `/health`    |
| Liveness   | Detect deadlocks, restart if failed    | `/health`    |
| Readiness  | Remove from load balancer if unhealthy | `/ready`     |

## Examples

- [Complete Example](./examples/complete/) - Full usage example with all options

## Contributing

1. Follow the existing code structure
2. Update tests for new functionality
3. Update documentation for any changes

## License

MIT License - See [LICENSE](../../../LICENSE) for details.
