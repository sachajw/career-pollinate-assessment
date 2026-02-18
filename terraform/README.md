# Terraform Infrastructure as Code

Infrastructure for the **FinRisk Platform** - Vendor Payment Risk Scoring Integration for FinSure Capital.

---

## Technical Assessment Compliance

### Infrastructure Requirements ✅

| Requirement                    | Status | Implementation                          |
| ------------------------------ | ------ | --------------------------------------- |
| Resource Group                 | ✅     | `rg-finrisk-{env}`                      |
| Azure Container App            | ✅     | `ca-finrisk-{env}` with scaling, probes |
| Azure Container Registry (ACR) | ✅     | `acrfinrisk{env}`                       |
| Azure Key Vault                | ✅     | `kv-finrisk-{env}` with RBAC            |
| Log Analytics Workspace        | ✅     | `log-finrisk-{env}`                     |
| Application Insights           | ✅     | `appi-finrisk-{env}`                    |
| Managed Identity               | ✅     | System-assigned on Container App        |
| Role assignments               | ✅     | AcrPull, Key Vault Secrets User         |

### Infrastructure Best Practices ✅

| Requirement               | Status | Implementation                          |
| ------------------------- | ------ | --------------------------------------- |
| Use remote state          | ✅     | Azure Storage backend                   |
| Use modules               | ✅     | 7 reusable modules                      |
| Be reusable (dev/prod)    | ✅     | `environments/dev`, `environments/prod` |
| Follow naming conventions | ✅     | `{type}-{project}-{env}`                |
| Avoid hardcoded secrets   | ✅     | Key Vault + Managed Identity            |

### Bonus Security Features ✅

| Feature                 | Status | Implementation             |
| ----------------------- | ------ | -------------------------- |
| Private endpoints       | ✅     | Key Vault, ACR             |
| Azure AD authentication | ✅     | EasyAuth on Container App  |
| Network restrictions    | ✅     | IP allowlist, network ACLs |

---

## Directory Structure

```
terraform/
├── modules/                    # Reusable Terraform modules
│   ├── resource-group/        # Azure resource group
│   ├── container-registry/    # Azure Container Registry (ACR)
│   ├── key-vault/             # Azure Key Vault for secrets
│   ├── observability/         # Log Analytics + Application Insights
│   ├── container-app/         # Azure Container Apps + Environment
│   ├── networking/            # Virtual Network, Subnets
│   └── private-endpoints/     # Private Link endpoints
│
├── environments/              # Environment-specific configurations
│   ├── dev/                   # Development environment
│   │   ├── main.tf            # Main configuration
│   │   ├── variables.tf       # Variable definitions
│   │   ├── outputs.tf         # Output values
│   │   ├── backend.tf         # Remote state configuration
│   │   └── terraform.tfvars.example
│   └── prod/                  # Production environment
│
└── tests/                     # Terratest integration tests (Go)
```

---

## Quick Start

### Prerequisites

```bash
# Install Terraform
brew install terraform
terraform --version  # >= 1.5.0

# Install Azure CLI
brew install azure-cli
az login
az account set --subscription "<subscription-id>"
```

### Bootstrap State Storage (One-Time)

```bash
# Create resource group
az group create --name rg-terraform-state --location eastus2

# Create storage account
STORAGE="stfinrisktf$RANDOM"
az storage account create \
  --name $STORAGE \
  --resource-group rg-terraform-state \
  --sku Standard_LRS \
  --allow-blob-public-access false

# Create container
az storage container create --name tfstate --account-name $STORAGE

echo "Storage Account: $STORAGE"  # Save for variable group
```

### Deploy Infrastructure

```bash
cd terraform/environments/dev

# Configure backend
cp backend.hcl.example backend.hcl
# Edit backend.hcl with storage account name

# Initialize
terraform init -backend-config=backend.hcl

# Validate
terraform validate

# Plan
terraform plan -out=tfplan

# Apply
terraform apply tfplan

# View outputs
terraform output
```

---

## Azure DevOps Setup (CI/CD)

### Service Connection

1. **Project Settings** → **Service connections**
2. Create **Azure Resource Manager** (Workload Identity)
3. Name: `azure-service-connection`

### Variable Group

| Name                 | Variable                       |
| -------------------- | ------------------------------ |
| `finrisk-iac-tf-dev` | `terraformStateStorageAccount` |

### Environments

| Name                  | Purpose                       |
| --------------------- | ----------------------------- |
| `finrisk-iac-tf-dev`  | Dev infrastructure approvals  |
| `finrisk-iac-tf-prod` | Prod infrastructure approvals |

### Extensions

- **Terraform** - [Marketplace](https://marketplace.visualstudio.com/items?itemName=ms-devlabs.custom-terraform-tasks)

---

## Modules

### resource-group

Creates Azure Resource Group.

| Input      | Description                                 |
| ---------- | ------------------------------------------- |
| `name`     | Resource group name (must start with `rg-`) |
| `location` | Azure region                                |
| `tags`     | Resource tags                               |

### container-registry

Creates Azure Container Registry for Docker images.

| Input                           | Description                     |
| ------------------------------- | ------------------------------- |
| `name`                          | Registry name (globally unique) |
| `sku`                           | Basic, Standard, or Premium     |
| `public_network_access_enabled` | Enable public access            |

### key-vault

Creates Azure Key Vault for secrets.

| Input                        | Description                              |
| ---------------------------- | ---------------------------------------- |
| `name`                       | Vault name (3-24 chars, globally unique) |
| `sku_name`                   | standard or premium                      |
| `soft_delete_retention_days` | 7-90 days                                |
| `purge_protection_enabled`   | Prevent permanent deletion               |

### observability

Creates Log Analytics and Application Insights.

| Input                          | Description       |
| ------------------------------ | ----------------- |
| `log_analytics_name`           | Workspace name    |
| `app_insights_name`            | App Insights name |
| `log_analytics_retention_days` | 30-730 days       |

### container-app

Creates Container App with environment.

| Input                   | Description         |
| ----------------------- | ------------------- |
| `name`                  | Container app name  |
| `container_image`       | Full image path     |
| `min_replicas`          | 0 for scale-to-zero |
| `max_replicas`          | 1-30                |
| `key_vault_id`          | For RBAC assignment |
| `container_registry_id` | For RBAC assignment |

### networking

Creates VNet with subnets for private endpoints and Container Apps.

### private-endpoints

Creates private endpoints for Key Vault and ACR.

---

## Resource Architecture

```
Resource Group (rg-finrisk-{env})
    │
    ├─> Log Analytics Workspace
    │       └─> Application Insights
    │
    ├─> Container Registry (ACR)
    │       ├─> Diagnostic Settings → Log Analytics
    │       └─> Private Endpoint (bonus)
    │
    ├─> Key Vault
    │       ├─> Diagnostic Settings → Log Analytics
    │       ├─> RBAC: Deployer (Key Vault Administrator)
    │       └─> Private Endpoint (bonus)
    │
    ├─> Virtual Network
    │       ├─> Subnet: Private Endpoints
    │       └─> Subnet: Container Apps
    │
    └─> Container App Environment
            └─> Container App
                    ├─> Managed Identity (system-assigned)
                    ├─> RBAC → ACR (AcrPull)
                    ├─> RBAC → Key Vault (Key Vault Secrets User)
                    └─> Azure AD Auth (bonus)
```

---

## Common Operations

### Add Secret to Key Vault

```bash
KEY_VAULT=$(terraform output -raw key_vault_name)

az keyvault secret set \
  --vault-name $KEY_VAULT \
  --name RISKSHIELD-API-KEY \
  --value "your-api-key"
```

### View Application Logs

```bash
az containerapp logs show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --follow
```

### Scale Container App

```bash
# Edit terraform.tfvars
min_replicas = 2
max_replicas = 10

terraform apply
```

### Destroy Infrastructure

```bash
terraform plan -destroy
terraform destroy
```

---

## Troubleshooting

### Backend initialization fails

```bash
# Verify storage account access
az storage account show --name $STORAGE --resource-group rg-terraform-state
```

### State locked

```bash
terraform force-unlock <lock-id>
```

### Resource already exists

```bash
terraform import module.resource_group.azurerm_resource_group.this /subscriptions/<id>/resourceGroups/rg-finrisk-dev
```

---

## Cost Estimation

**Dev Environment (scale-to-zero):**

| Resource                   | Monthly Cost  |
| -------------------------- | ------------- |
| Container App              | ~$0           |
| Container Registry (Basic) | ~$5           |
| Key Vault                  | ~$0           |
| Log Analytics              | ~$3           |
| **Total**                  | **~$8/month** |

---

**Last Updated:** 2026-02-18
**Terraform Version:** >= 1.5.0
**Azure Provider Version:** ~> 4.0
