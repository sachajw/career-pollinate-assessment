# Azure Container App Module

A Terraform module for creating Azure Container Apps with managed identity, autoscaling, health probes, ingress configuration, and integrated RBAC for ACR and Key Vault access.

## Features

- System-assigned managed identity for Azure service authentication
- HTTP-based and custom autoscaling rules
- Startup, liveness, and readiness health probes
- HTTPS-only ingress with optional custom domain
- Blue/green deployment support via traffic weighting
- IP security restrictions
- Dapr sidecar support (optional)
- Automatic RBAC assignments for ACR and Key Vault
- VNet integration and private ingress support
- Custom domain with certificate support

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

  container_name   = "api"
  container_image  = "myapp/api:latest"
  container_cpu    = 0.5
  container_memory = "1Gi"

  min_replicas = 0  # Scale to zero
  max_replicas = 3

  ingress_enabled     = true
  ingress_target_port = 8080

  tags = {
    Environment = "dev"
  }
}
```

### Production Example with Custom Domain

```hcl
module "container_app" {
  source = "../../modules/container-app"

  name                = "ca-myapp-prod"
  environment_name    = "cae-myapp-prod"
  resource_group_name = "rg-myapp-prod"
  location            = "eastus2"

  log_analytics_workspace_id     = module.observability.log_analytics_workspace_id
  infrastructure_subnet_id       = module.vnet.container_apps_subnet_id
  internal_load_balancer_enabled = false
  zone_redundancy_enabled        = true

  # Container configuration
  container_name   = "api"
  container_image  = "${module.container_registry.login_server}/myapp/api:v1.2.3"
  container_cpu    = 1.0
  container_memory = "2Gi"

  # Scaling
  min_replicas                   = 2
  max_replicas                   = 20
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

  readiness_probe_enabled = true
  readiness_probe_path    = "/ready"
  readiness_probe_port    = 8080

  # Ingress
  ingress_enabled            = true
  ingress_external_enabled   = true
  ingress_target_port        = 8080
  allow_insecure_connections = false

  # Custom domain
  custom_domain_enabled = true
  custom_domain_name    = "api.example.com"
  certificate_name      = "api-example-com-cert"

  # Registry and secrets
  registry_server       = module.container_registry.login_server
  enable_acr_pull       = true
  container_registry_id = module.container_registry.id

  enable_key_vault_access = true
  key_vault_id            = module.key_vault.id

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
| azurerm   | ~> 3.100 |

## Inputs

### Required Variables

| Name                | Description                           | Type          | Default |
| ------------------- | ------------------------------------- | ------------- | ------- |
| name                | Name of the container app             | `string`      | n/a     |
| environment_name    | Name of the container app environment | `string`      | n/a     |
| resource_group_name | Name of the resource group            | `string`      | n/a     |
| location            | Azure region                          | `string`      | n/a     |
| log_analytics_workspace_id | Log Analytics workspace ID     | `string`      | n/a     |
| container_image     | Full container image path             | `string`      | n/a     |

### Common Variables

| Name  | Description       | Type          | Default |
| ----- | ----------------- | ------------- | ------- |
| tags  | Tags to apply     | `map(string)` | `{}`    |

### Environment Configuration

| Name                           | Description                    | Type     | Default | Required |
| ------------------------------ | ------------------------------ | -------- | ------- | :------: |
| infrastructure_subnet_id       | Subnet ID for VNet integration | `string` | `null`  |    no    |
| internal_load_balancer_enabled | Enable private ingress         | `bool`   | `false` |    no    |
| zone_redundancy_enabled        | Enable zone redundancy         | `bool`   | `false` |    no    |

### Container Configuration

| Name                         | Description                            | Type          | Default    |
| ---------------------------- | -------------------------------------- | ------------- | ---------- |
| revision_mode                | Revision mode (Single or Multiple)     | `string`      | `"Single"` |
| revision_suffix              | Custom suffix for revision names       | `string`      | `null`     |
| container_name               | Name of the container                  | `string`      | `"api"`    |
| container_cpu                | CPU allocation (0.25-2.0)              | `number`      | `0.5`      |
| container_memory             | Memory allocation                      | `string`      | `"1Gi"`    |
| environment_variables        | Non-sensitive environment variables    | `map(string)` | `{}`       |
| secret_environment_variables | Secret environment variable references | `map(string)` | `{}`       |
| secrets                      | Secrets to store in Container App      | `map(string)` | `{}`       |

### Scaling Configuration

| Name                           | Description                            | Type           | Default |
| ------------------------------ | -------------------------------------- | -------------- | ------- |
| min_replicas                   | Minimum replicas (0 for scale-to-zero) | `number`       | `1`     |
| max_replicas                   | Maximum replicas                       | `number`       | `10`    |
| http_scale_rule_enabled        | Enable HTTP autoscaling                | `bool`         | `true`  |
| http_scale_concurrent_requests | Concurrent requests before scaling     | `number`       | `100`   |
| custom_scale_rules             | Custom KEDA scale rules                | `list(object)` | `[]`    |

### Health Probes - Startup

| Name                          | Description                  | Type     | Default     |
| ----------------------------- | ---------------------------- | -------- | ----------- |
| startup_probe_enabled         | Enable startup probe         | `bool`   | `false`     |
| startup_probe_transport       | Transport (HTTP or TCP)      | `string` | `"HTTP"`    |
| startup_probe_port            | Probe port                   | `number` | `8080`      |
| startup_probe_path            | Probe HTTP path              | `string` | `"/health"` |
| startup_probe_initial_delay   | Initial delay in seconds     | `number` | `5`         |
| startup_probe_interval        | Interval in seconds          | `number` | `10`        |
| startup_probe_timeout         | Timeout in seconds           | `number` | `3`         |
| startup_probe_failure_threshold | Failure threshold           | `number` | `3`         |

### Health Probes - Liveness

| Name                           | Description                  | Type     | Default     |
| ------------------------------ | ---------------------------- | -------- | ----------- |
| liveness_probe_enabled         | Enable liveness probe        | `bool`   | `true`      |
| liveness_probe_transport       | Transport (HTTP or TCP)      | `string` | `"HTTP"`    |
| liveness_probe_port            | Probe port                   | `number` | `8080`      |
| liveness_probe_path            | Probe HTTP path              | `string` | `"/health"` |
| liveness_probe_initial_delay   | Initial delay in seconds     | `number` | `10`        |
| liveness_probe_interval        | Interval in seconds          | `number` | `30`        |
| liveness_probe_timeout         | Timeout in seconds           | `number` | `3`         |
| liveness_probe_failure_threshold | Failure threshold           | `number` | `3`         |

### Health Probes - Readiness

| Name                            | Description                  | Type     | Default    |
| ------------------------------- | ---------------------------- | -------- | ---------- |
| readiness_probe_enabled         | Enable readiness probe       | `bool`   | `true`     |
| readiness_probe_transport       | Transport (HTTP or TCP)      | `string` | `"HTTP"`   |
| readiness_probe_port            | Probe port                   | `number` | `8080`     |
| readiness_probe_path            | Probe HTTP path              | `string` | `"/ready"` |
| readiness_probe_interval        | Interval in seconds          | `number` | `10`       |
| readiness_probe_timeout         | Timeout in seconds           | `number` | `3`        |
| readiness_probe_failure_threshold | Failure threshold           | `number` | `3`        |
| readiness_probe_success_threshold | Success threshold           | `number` | `1`        |

### Ingress Configuration

| Name                       | Description                      | Type     | Default  |
| -------------------------- | -------------------------------- | -------- | -------- |
| ingress_enabled            | Enable ingress                   | `bool`   | `true`   |
| ingress_external_enabled   | Enable external (public) ingress | `bool`   | `true`   |
| ingress_target_port        | Target port                      | `number` | `8080`   |
| ingress_transport          | Transport (http, http2, tcp)     | `string` | `"http"` |
| allow_insecure_connections | Allow HTTP (not just HTTPS)      | `bool`   | `false`  |
| traffic_latest_revision    | Route to latest revision         | `bool`   | `true`   |
| traffic_percentage         | Traffic percentage               | `number` | `100`    |
| traffic_label              | Label for traffic split          | `string` | `null`   |
| ip_security_restrictions   | IP security restrictions         | `list(object)` | `[]` |

### CORS Configuration

| Name                    | Description              | Type           | Default                              |
| ----------------------- | ------------------------ | -------------- | ------------------------------------ |
| cors_enabled            | Enable CORS              | `bool`         | `false`                              |
| cors_allowed_origins    | Allowed origins          | `list(string)` | `["*"]`                              |
| cors_allowed_methods    | Allowed methods          | `list(string)` | `["GET", "POST", "PUT", "DELETE", "OPTIONS"]` |
| cors_allowed_headers    | Allowed headers          | `list(string)` | `["*"]`                              |
| cors_expose_headers     | Exposed headers          | `list(string)` | `[]`                                 |
| cors_max_age            | Max age in seconds       | `number`       | `3600`                               |
| cors_allow_credentials  | Allow credentials        | `bool`         | `false`                              |

### Registry and Key Vault

| Name                    | Description                            | Type     | Default |
| ----------------------- | -------------------------------------- | -------- | ------- |
| registry_server         | Container registry server              | `string` | `""`    |
| enable_acr_pull         | Enable ACR pull role assignment        | `bool`   | `false` |
| container_registry_id   | ACR ID for RBAC                        | `string` | `""`    |
| enable_key_vault_access | Enable Key Vault secrets user role     | `bool`   | `false` |
| key_vault_id            | Key Vault ID for RBAC                  | `string` | `""`    |

### Dapr Configuration

| Name              | Description           | Type     | Default  |
| ----------------- | --------------------- | -------- | -------- |
| dapr_enabled      | Enable Dapr sidecar   | `bool`   | `false`  |
| dapr_app_id       | Dapr application ID   | `string` | `null`   |
| dapr_app_protocol | Dapr protocol         | `string` | `"http"` |
| dapr_app_port     | Dapr application port | `number` | `null`   |

### Custom Domain Configuration

| Name                   | Description                                           | Type     | Default |
| ---------------------- | ----------------------------------------------------- | -------- | ------- |
| custom_domain_enabled  | Enable custom domain with certificate                 | `bool`   | `false` |
| custom_domain_name     | Custom domain name (e.g., api.example.com)            | `string` | `""`    |
| certificate_name       | Name of existing certificate in Container App Env     | `string` | `""`    |

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

When `enable_acr_pull = true` and `container_registry_id` is provided:
- Assigns `AcrPull` role to the container app's managed identity

When `enable_key_vault_access = true` and `key_vault_id` is provided:
- Assigns `Key Vault Secrets User` role to the container app's managed identity

## Health Probe Configuration

| Probe Type | Purpose                                | Default Path | Default Port |
| ---------- | -------------------------------------- | ------------ | ------------ |
| Startup    | Wait for container startup             | `/health`    | `8080`       |
| Liveness   | Detect deadlocks, restart if failed    | `/health`    | `8080`       |
| Readiness  | Remove from load balancer if unhealthy | `/ready`     | `8080`       |

## Custom Domain Setup

1. Upload certificate to Container App Environment via Azure CLI:
   ```bash
   az containerapp env certificate upload \
     --name cae-myapp-prod \
     --resource-group rg-myapp-prod \
     --certificate-file /path/to/cert.pfx \
     --certificate-name my-cert
   ```

2. Configure Terraform:
   ```hcl
   custom_domain_enabled = true
   custom_domain_name    = "api.example.com"
   certificate_name      = "my-cert"
   ```

3. Get verification ID and configure DNS:
   ```bash
   terraform output custom_domain_verification_id
   ```

## Contributing

1. Follow the existing code structure
2. Update tests for new functionality
3. Update documentation for any changes

## License

MIT License
