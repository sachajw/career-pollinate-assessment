# ADR-006: Terraform Module Architecture

**Status:** Accepted
**Date:** 2026-02-14
**Decision Makers:** Platform Engineering Team
**Technical Story:** RiskShield API Integration Platform

## Context

The RiskShield integration platform requires Infrastructure as Code (IaC) that is:
- Maintainable and understandable
- Reusable across environments (dev, staging, prod)
- Following Azure resource naming conventions
- Using remote state for team collaboration
- Modular for testing and reusability

The technical assessment requires:
- Remote state (Azure Storage backend)
- Modular structure
- Reusable for dev/prod environments
- Naming conventions
- No hardcoded secrets

## Decision

We will use a **modular Terraform architecture** with **Azure Storage remote backend** and **environment-based workspaces**.

## Directory Structure

```
terraform/
├── modules/                          # Reusable modules
│   ├── container-app/                # Azure Container Apps
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── container-registry/           # Azure Container Registry
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── key-vault/                    # Azure Key Vault
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── networking/                   # Virtual Network + Subnets
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── observability/                # Log Analytics + App Insights
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── private-endpoints/            # Private Link endpoints
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── resource-group/               # Resource Group
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
└── environments/                     # Environment configurations
    ├── dev/
    │   ├── main.tf                   # Root module composition
    │   ├── variables.tf
    │   ├── outputs.tf
    │   ├── backend.hcl               # Remote state config
    │   ├── terraform.tfvars          # Environment values
    │   └── terraform.tfvars.example  # Template for new environments
    │
    └── prod/
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        ├── backend.hcl
        └── terraform.tfvars
```

## Decision 1: Remote State with Azure Storage

### Why Remote State?

| Aspect              | Local State           | Remote State           |
| ------------------- | --------------------- | ---------------------- |
| **Team Collaboration** | ❌ Conflicts         | ✅ Locking prevents conflicts |
| **Security**        | ❌ Secrets in files   | ✅ Encrypted at rest   |
| **Backup**          | ❌ Manual            | ✅ Automatic           |
| **CI/CD**           | ❌ Difficult         | ✅ Accessible anywhere |

### Backend Configuration

```hcl
# environments/dev/backend.hcl
resource_group_name  = "rg-terraform-state"
storage_account_name = "sttfstatefinrisk001"
container_name       = "tfstate"
key                  = "finrisk-dev.tfstate"
```

### State File Security

```hcl
# Terraform state storage (created once)
resource "azurerm_storage_account" "tfstate" {
  name                     = "sttfstatefinrisk001"
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = "eastus2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Security settings
  min_tls_version                 = "TLS1_2"
  enable_https_traffic_only       = true
  allow_nested_items_to_be_public = false

  # Soft delete for recovery
  blob_properties {
    delete_retention_policy {
      days = 30
    }
  }
}
```

### State Locking

Azure Storage backend provides automatic state locking:
- Locks during `terraform apply`
- Prevents concurrent modifications
- Releases lock on completion or failure

## Decision 2: Module Architecture

### Module Design Principles

1. **Single Responsibility**: Each module manages one Azure resource type
2. **Composable**: Modules can be combined in any configuration
3. **Versioned**: Modules are versioned for stability
4. **Documented**: Every module has a README with examples

### Module Interface Example

```hcl
# modules/container-app/variables.tf
variable "name" {
  description = "Name of the Container App"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "container_app_environment_id" {
  description = "Container App Environment ID"
  type        = string
}

variable "container_image" {
  description = "Container image to deploy"
  type        = string
}

variable "key_vault_url" {
  description = "Key Vault URL for secrets"
  type        = string
}

variable "app_insights_connection_string" {
  description = "Application Insights connection string"
  type        = string
  sensitive   = true
}

variable "min_replicas" {
  description = "Minimum number of replicas"
  type        = number
  default     = 0
}

variable "max_replicas" {
  description = "Maximum number of replicas"
  type        = number
  default     = 10
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
```

### Module Output Example

```hcl
# modules/container-app/outputs.tf
output "container_app_id" {
  description = "Container App ID"
  value       = azurerm_container_app.main.id
}

output "container_app_name" {
  description = "Container App name"
  value       = azurerm_container_app.main.name
}

output "container_app_url" {
  description = "Container App URL"
  value       = "https://${azurerm_container_app.main.latest_revision_fqdn}"
}

output "principal_id" {
  description = "Managed Identity principal ID for RBAC assignments"
  value       = azurerm_container_app.main.identity[0].principal_id
}
```

## Decision 3: Naming Convention

### Naming Pattern

```
{resource-type}-{domain}-{environment}
```

### Examples

| Resource Type        | Prefix | Dev Name              | Prod Name             |
| -------------------- | ------ | --------------------- | --------------------- |
| Resource Group       | rg     | rg-finrisk-dev        | rg-finrisk-prod       |
| Container App        | ca     | ca-finrisk-dev        | ca-finrisk-prod       |
| Container Registry   | acr    | acrfinriskdev001      | acrfinriskprod001     |
| Key Vault            | kv     | kv-finrisk-dev        | kv-finrisk-prod       |
| Log Analytics        | log    | log-finrisk-dev       | log-finrisk-prod      |
| App Insights         | ai     | ai-finrisk-dev        | ai-finrisk-prod       |

### Implementation

```hcl
# environments/dev/variables.tf
locals {
  naming_prefix = "finrisk-dev"

  tags = {
    Environment = "dev"
    Project     = "RiskShield Integration"
    ManagedBy   = "Terraform"
    CostCenter  = "Platform Engineering"
  }
}
```

## Decision 4: Environment Strategy

### Environment Isolation

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure Subscription                        │
│                                                              │
│  ┌────────────────────┐      ┌────────────────────┐         │
│  │   rg-finrisk-dev   │      │  rg-finrisk-prod   │         │
│  │                    │      │                    │         │
│  │  • ca-finrisk-dev  │      │  • ca-finrisk-prod │         │
│  │  • kv-finrisk-dev  │      │  • kv-finrisk-prod │         │
│  │  • acrfinriskdev   │      │  • acrfinriskprod  │         │
│  │  • log-finrisk-dev │      │  • log-finrisk-prod│         │
│  └────────────────────┘      └────────────────────┘         │
│                                                              │
│  ┌────────────────────────────────────────────────────┐     │
│  │         rg-terraform-state (Shared)                 │     │
│  │  • sttfstatefinrisk001 (state storage)             │     │
│  └────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

### Environment-Specific Configuration

```hcl
# environments/dev/terraform.tfvars
environment = "dev"
location    = "eastus2"

# Container App scaling (dev = cost optimization)
container_app = {
  min_replicas = 0  # Scale to zero
  max_replicas = 3
  cpu          = 0.25
  memory       = "0.5Gi"
}

# Key Vault
key_vault = {
  sku = "standard"
}

# Tags
tags = {
  Environment = "dev"
  CostCenter  = "Development"
}
```

```hcl
# environments/prod/terraform.tfvars
environment = "prod"
location    = "eastus2"

# Container App scaling (prod = high availability)
container_app = {
  min_replicas = 2  # Always on
  max_replicas = 10
  cpu          = 0.5
  memory       = "1.0Gi"
}

# Key Vault
key_vault = {
  sku = "premium"  # HSM-backed keys
}

# Tags
tags = {
  Environment = "prod"
  CostCenter  = "Production"
}
```

## Decision 5: No Hardcoded Secrets

### Secrets Management Strategy

```hcl
# ❌ BAD: Hardcoded secret
resource "azurerm_key_vault_secret" "api_key" {
  name         = "RISKSHIELD_API_KEY"
  value        = "sk-abc123secret"  # NEVER do this!
  key_vault_id = azurerm_key_vault.main.id
}

# ✅ GOOD: Secret from variable (set via CI/CD)
variable "riskshield_api_key" {
  type      = string
  sensitive = true  # Marks as sensitive, hides from logs
}

resource "azurerm_key_vault_secret" "api_key" {
  name         = "RISKSHIELD_API_KEY"
  value        = var.riskshield_api_key
  key_vault_id = azurerm_key_vault.main.id
}
```

### CI/CD Integration

```yaml
# Azure DevOps pipeline
- stage: Infrastructure
  variables:
    - group: finrisk-secrets  # Variable group with secrets
  steps:
    - task: TerraformTaskV4@4
      inputs:
        provider: 'azurerm'
        command: 'apply'
        commandOptions: >
          -var="riskshield_api_key=$(RISKSHIELD_API_KEY)"
          -auto-approve
```

## Module Composition Example

```hcl
# environments/dev/main.tf
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

# Local variables for naming
locals {
  naming_prefix = "finrisk-${var.environment}"
  tags = merge(var.tags, {
    Environment = var.environment
  })
}

# Module composition
module "resource_group" {
  source   = "../../modules/resource-group"
  name     = "rg-${local.naming_prefix}"
  location = var.location
  tags     = local.tags
}

module "key_vault" {
  source              = "../../modules/key-vault"
  name                = "kv-${local.naming_prefix}"
  location            = var.location
  resource_group_name = module.resource_group.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = local.tags
}

module "container_registry" {
  source              = "../../modules/container-registry"
  name                = "acr${replace(local.naming_prefix, "-", "")}001"
  location            = var.location
  resource_group_name = module.resource_group.name
  tags                = local.tags
}

module "observability" {
  source              = "../../modules/observability"
  naming_prefix       = local.naming_prefix
  location            = var.location
  resource_group_name = module.resource_group.name
  tags                = local.tags
}

module "container_app" {
  source                        = "../../modules/container-app"
  name                          = "ca-${local.naming_prefix}"
  location                      = var.location
  resource_group_name           = module.resource_group.name
  container_app_environment_id  = module.container_app_environment.id
  container_image               = "${module.container_registry.login_server}/applicant-validator:latest"
  key_vault_url                 = module.key_vault.uri
  app_insights_connection_string = module.observability.app_insights_connection_string
  min_replicas                  = var.container_app.min_replicas
  max_replicas                  = var.container_app.max_replicas
  tags                          = local.tags

  depends_on = [
    module.key_vault,
    module.container_registry
  ]
}

# RBAC: Grant Container App access to Key Vault
resource "azurerm_role_assignment" "keyvault_secrets_user" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.container_app.principal_id
}

# RBAC: Grant Container App access to ACR
resource "azurerm_role_assignment" "acr_pull" {
  scope                = module.container_registry.id
  role_definition_name = "AcrPull"
  principal_id         = module.container_app.principal_id
}
```

## Terraform Commands

### Development Workflow

```bash
cd terraform/environments/dev

# Initialize with backend config
terraform init -backend-config=backend.hcl

# Format code
terraform fmt -recursive

# Validate configuration
terraform validate

# Plan changes
terraform plan -out=tfplan

# Apply changes
terraform apply tfplan

# View outputs
terraform output

# Destroy (caution!)
terraform destroy
```

### State Management

```bash
# List resources in state
terraform state list

# Show specific resource
terraform state show module.container_app.azurerm_container_app.main

# Import existing resource
terraform import azurerm_resource_group.existing /subscriptions/.../resourceGroups/rg-existing

# Move resource in state
terraform state mv module.old.module.new

# Remove resource from state (doesn't delete real resource)
terraform state rm azurerm_resource_group.deprecated
```

## Consequences

### Positive

- ✅ **Modularity**: Each resource in its own module
- ✅ **Reusability**: Same modules for dev/prod
- ✅ **Collaboration**: Remote state with locking
- ✅ **Security**: Secrets from CI/CD, encrypted state
- ✅ **Maintainability**: Clear naming conventions
- ✅ **Testing**: Modules can be tested independently

### Negative

- ⚠️ **Complexity**: More files to manage
- ⚠️ **Initial Setup**: Backend storage must be created first
- ⚠️ **Learning Curve**: Team needs Terraform knowledge

### Mitigations

- Comprehensive README for each module
- Example terraform.tfvars for new environments
- Terraform training for team members

## Compliance with Technical Assessment

| Requirement              | Status | Implementation                        |
| ------------------------ | ------ | ------------------------------------- |
| Remote state             | ✅     | Azure Storage backend with locking    |
| Modules                  | ✅     | 7 reusable modules                    |
| Reusable (dev/prod)      | ✅     | Environment-based configuration       |
| Naming conventions       | ✅     | `{type}-{domain}-{env}` pattern       |
| No hardcoded secrets     | ✅     | Sensitive variables + CI/CD injection |

## Related Decisions

- [ADR-001: Azure Container Apps](./001-azure-container-apps.md)
- [ADR-003: Managed Identity for Security](./003-managed-identity-security.md)
- [ADR-007: CI/CD Pipeline Strategy](./007-cicd-pipeline-strategy.md)

## References

- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/)
- [Terraform Module Best Practices](https://developer.hashicorp.com/terraform/language/modules/develop)
- [Azure Resource Naming Convention](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming)
- [Terraform State Management](https://developer.hashicorp.com/terraform/language/state)

## Review & Approval

| Role                      | Name   | Date       | Status      |
| ------------------------- | ------ | ---------- | ----------- |
| Solution Architect        | [Name] | 2026-02-14 | ✅ Approved |
| Platform Engineering Lead | [Name] | 2026-02-14 | ✅ Approved |
| DevOps Lead               | [Name] | 2026-02-14 | ✅ Approved |

---

**Last Updated:** 2026-02-18
**Next Review:** 2026-08-18 (6 months)
