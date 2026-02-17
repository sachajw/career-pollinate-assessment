# Terraform Infrastructure as Code

This directory contains Terraform configuration for the **FinRisk Platform** infrastructure on Microsoft Azure.

**Domain Service**: Applicant Validator - Loan applicant fraud risk validation for FinSure Capital.

## 📁 Directory Structure

```
terraform/
├── modules/                    # Reusable Terraform modules
│   ├── resource-group/        # Azure resource group
│   ├── container-registry/    # Azure Container Registry (ACR)
│   ├── key-vault/             # Azure Key Vault for secrets
│   ├── observability/         # Log Analytics + Application Insights
│   ├── container-app/         # Azure Container Apps + Environment
│   └── azure-devops/          # Azure DevOps CI/CD configuration
│
├── environments/              # Environment-specific configurations
│   └── dev/                   # Development environment
│       ├── main.tf            # Main configuration
│       ├── variables.tf       # Variable definitions
│       ├── outputs.tf         # Output values
│       ├── backend.tf         # Remote state configuration
│       ├── backend.hcl.example      # Backend config template
│       └── terraform.tfvars.example # Variables template
│
├── devops/                    # Azure DevOps Terraform configuration
├── tests/                     # Terratest infrastructure tests (Go)
├── scripts/                   # Helper scripts (e.g. certificate upload)
├── versions.tf                # Terraform and provider versions
├── providers.tf               # Provider configuration
├── BOOTSTRAP.md               # One-time prerequisites setup guide
├── TESTING.md                 # Infrastructure testing guide
└── README.md                  # This file
```

## 🚀 Quick Start

### Prerequisites

1. **Install Terraform**

   ```bash
   # macOS
   brew install terraform

   # Or download from https://www.terraform.io/downloads
   terraform --version  # Should be >= 1.5.0
   ```

2. **Install Azure CLI**

   ```bash
   # macOS
   brew install azure-cli

   # Or download from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli
   az --version
   ```

3. **Login to Azure**
   ```bash
   az login
   az account set --subscription "<subscription-id>"
   az account show  # Verify correct subscription
   ```

### Initial Setup

#### Step 1: Bootstrap Terraform State (One-Time)

Run the bootstrap script to create the Azure resources needed for Terraform remote state:

```bash
# Prerequisites check
az login                    # Login to Azure
az account show             # Verify correct subscription

# Run bootstrap script
./scripts/bootstrap-terraform-state.sh eastus2
```

**What it creates:**
- Resource Group: `rg-terraform-state`
- Storage Account: `sttfstatefinrisk<random>`
- Blob Container: `tfstate`

**Output:** The script outputs the `backend.hcl` configuration for both dev and prod environments.

#### Step 2: Configure Backend for Each Environment

```bash
# Copy the output from bootstrap script to backend.hcl files

# For Dev
cp terraform/environments/dev/backend.hcl.example terraform/environments/dev/backend.hcl
# Edit with values from bootstrap script output

# For Prod
cp terraform/environments/prod/backend.hcl.example terraform/environments/prod/backend.hcl
# Edit with values from bootstrap script output
```

#### Step 3: Initialize Terraform

```bash
# Dev environment
cd terraform/environments/dev
terraform init -backend-config=backend.hcl
terraform validate

# Prod environment
cd ../prod
terraform init -backend-config=backend.hcl
terraform validate
```

#### Step 2: Configure Backend

```bash
cd environments/dev

# Copy backend configuration template
cp backend.hcl.example backend.hcl

# Edit backend.hcl with your storage account name
# Replace <your-unique-suffix> with your actual storage account suffix
nano backend.hcl
```

#### Step 3: Configure Variables

```bash
# Copy variables template
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars (optional, defaults are provided)
nano terraform.tfvars
```

#### Step 4: Initialize Terraform

```bash
# Initialize Terraform with backend configuration
terraform init -backend-config=backend.hcl

# This will:
# - Download required providers
# - Configure remote state backend
# - Prepare working directory
```

### Deploy Infrastructure

```bash
# Navigate to dev environment
cd environments/dev

# Format code
terraform fmt -recursive

# Validate configuration
terraform validate

# Plan changes (review before applying)
terraform plan -out=tfplan

# Apply changes (create infrastructure)
terraform apply tfplan

# After successful apply, save outputs
terraform output -json > outputs.json
```

### Outputs

After deployment, Terraform will display important outputs:

```bash
# View all outputs
terraform output

# View specific output
terraform output container_app_url
terraform output key_vault_name

# Get quick start commands
terraform output -raw quick_start_commands
```

## 🔐 Security Best Practices

### Secrets Management

**❌ DO NOT:**

- Commit `terraform.tfvars` with sensitive values
- Hardcode secrets in `.tf` files
- Store state files locally
- Share access keys in plain text

**✅ DO:**

- Use Azure Key Vault for application secrets
- Use backend.hcl for backend configuration (gitignored)
- Use Azure AD authentication for state storage
- Use Managed Identity for service authentication
- Store sensitive tfvars in Azure DevOps variable groups

### State File Protection

State files contain sensitive information:

```bash
# Enable versioning on state storage (recommended)
az storage blob service-properties update \
  --account-name stterraformstate<your-unique-name> \
  --enable-versioning true

# Enable soft delete (30-day retention)
az storage blob service-properties delete-policy update \
  --account-name stterraformstate<your-unique-name> \
  --enable true \
  --days-retained 30
```

## Resource Dependency Graph

```
Resource Group
    ↓
    ├─> Log Analytics Workspace
    │       ↓
    │       └─> Application Insights
    │
    ├─> Container Registry (ACR)
    │       └─> Diagnostic Settings → Log Analytics
    │
    ├─> Key Vault
    │       ├─> Diagnostic Settings → Log Analytics
    │       └─> RBAC: Deployer (Key Vault Administrator)
    │
    └─> Container App Environment → Log Analytics
            ↓
            └─> Container App
                    ├─> RBAC → ACR (AcrPull)
                    ├─> RBAC → Key Vault (Key Vault Secrets User)
                    └─> Managed Identity (System-Assigned)
```

## 📦 Module Documentation

### resource-group

Creates an Azure Resource Group.

**Inputs:**

- `name`: Resource group name (must start with `rg-`)
- `location`: Azure region
- `tags`: Resource tags

**Outputs:**

- `id`: Resource group ID
- `name`: Resource group name
- `location`: Azure region

### container-registry

Creates an Azure Container Registry (ACR) for Docker images.

**Inputs:**

- `name`: Registry name (alphanumeric, globally unique)
- `sku`: SKU tier (Basic, Standard, Premium)
- `public_network_access_enabled`: Enable public access
- `log_analytics_workspace_id`: Optional Log Analytics workspace

**Outputs:**

- `id`: Registry ID
- `login_server`: Registry URL
- `name`: Registry name

### key-vault

Creates an Azure Key Vault for secure secret storage.

**Inputs:**

- `name`: Vault name (3-24 chars, globally unique)
- `sku_name`: SKU (standard or premium)
- `soft_delete_retention_days`: Retention period (7-90 days)
- `purge_protection_enabled`: Enable purge protection
- `deployer_object_id`: Principal ID for RBAC

**Outputs:**

- `id`: Vault ID
- `vault_uri`: Vault URI
- `name`: Vault name

### observability

Creates Log Analytics workspace and Application Insights.

**Inputs:**

- `log_analytics_name`: Workspace name
- `app_insights_name`: App Insights name
- `log_analytics_retention_days`: Log retention (30-730 days)
- `sampling_percentage`: Telemetry sampling (1-100%)

**Outputs:**

- `log_analytics_workspace_id`: Workspace ID
- `app_insights_connection_string`: Connection string (sensitive)
- `app_insights_instrumentation_key`: Instrumentation key (sensitive)

### container-app

Creates Azure Container App with environment.

**Inputs:**

- `name`: Container app name
- `container_image`: Full image path
- `container_cpu`: CPU allocation (0.25-2.0)
- `container_memory`: Memory allocation (0.5Gi-4Gi)
- `min_replicas`: Min replicas (0 for scale-to-zero)
- `max_replicas`: Max replicas (1-30)
- `ingress_enabled`: Enable HTTP ingress
- `key_vault_id`: Key Vault for RBAC
- `container_registry_id`: ACR for RBAC

**Outputs:**

- `application_url`: Public HTTPS URL
- `identity_principal_id`: Managed identity principal ID
- `ingress_fqdn`: Application FQDN

## 🛠️ Common Operations

### Container Image Updates (CI/CD Managed)

Container images are managed by the CI/CD pipeline using **semantic versioning from git tags**. Terraform does not update application images.

**Workflow:**

```bash
# Development: Push code, pipeline auto-versions
git commit -m "feat: new feature"
git push  # → applicant-validator:v0.1.0-5-gabc123

# Release: Create git tag
git tag v1.0.0
git push origin v1.0.0  # → applicant-validator:v1.0.0
```

**Why Terraform doesn't manage images:**

1. `ignore_changes` in `container-app/main.tf` prevents drift detection
2. CI/CD uses `az containerapp update` for zero-downtime deployments
3. Git is the source of truth for versioning

**Initial deployment only:**

```bash
# Terraform sets :latest tag for initial infrastructure deployment
# CI/CD then takes over for application updates
terraform apply
```

### Scale Container App

```bash
# Edit terraform.tfvars
container_app_min_replicas = 2
container_app_max_replicas = 10

# Apply changes
terraform apply
```

### Add Secret to Key Vault

```bash
# Get Key Vault name from Terraform output
KEY_VAULT_NAME=$(terraform output -raw key_vault_name)

# Add secret
az keyvault secret set \
  --vault-name $KEY_VAULT_NAME \
  --name RISKSHIELD-API-KEY \
  --value "your-api-key-here"

# Verify
az keyvault secret show \
  --vault-name $KEY_VAULT_NAME \
  --name RISKSHIELD-API-KEY \
  --query value \
  --output tsv
```

### View Application Logs

```bash
# The quick_start_commands output includes a pre-built logs command:
terraform output -raw quick_start_commands

# Or run the logs command directly (naming follows convention ca-{project}-{env}):
RG_NAME=$(terraform output -raw resource_group_name)
az containerapp logs show \
  --name ca-finrisk-dev \
  --resource-group $RG_NAME \
  --follow
```

### Destroy Infrastructure

```bash
# ⚠️ WARNING: This will delete ALL resources
# Review what will be destroyed
terraform plan -destroy

# Destroy infrastructure
terraform destroy

# Type 'yes' to confirm
```

## 🔄 State Management

### View State

```bash
# List all resources in state
terraform state list

# Show specific resource
terraform state show module.container_app.azurerm_container_app.this

# Pull current state
terraform state pull > state-backup.json
```

### Import Existing Resources

```bash
# Import existing resource group
terraform import module.resource_group.azurerm_resource_group.this /subscriptions/<sub-id>/resourceGroups/rg-finrisk-dev

# Import existing Key Vault
terraform import module.key_vault.azurerm_key_vault.this /subscriptions/<sub-id>/resourceGroups/rg-finrisk-dev/providers/Microsoft.KeyVault/vaults/kv-finrisk-dev
```

### State Locking

Azure Storage automatically provides state locking via blob lease. No additional configuration required.

## 🧪 Testing

### Validate Configuration

```bash
# Format check
terraform fmt -check -recursive

# Validation
terraform validate

# Plan (dry-run)
terraform plan
```

### Security Scanning

```bash
# Install tfsec
brew install tfsec

# Scan for security issues
tfsec .

# Install Checkov
pip install checkov

# Scan with Checkov
checkov --directory .
```

## 📊 Cost Estimation

### Azure Pricing Calculator

Use the [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/) to estimate costs.

**Estimated Monthly Cost (Dev):**

- Resource Group: Free
- Container App: ~$30 (scale-to-zero)
- Container Registry (Basic): ~$5
- Key Vault: ~$3
- Log Analytics (1GB/day): ~$10
- Application Insights: ~$5
- **Total: ~$53/month**

### Terraform Cost Estimation

```bash
# Install Infracost
brew install infracost

# Register for API key
infracost register

# Generate cost estimate
infracost breakdown --path .

# Compare against current state
infracost diff --path .
```

## 🚨 Troubleshooting

### Common Issues

**Issue: Backend initialization fails**

```bash
# Check storage account access
az storage account show --name stterraformstate<name> --resource-group rg-terraform-state

# Verify you have Storage Blob Data Contributor role
az role assignment list --assignee $(az ad signed-in-user show --query id --output tsv) --scope /subscriptions/<sub-id>/resourceGroups/rg-terraform-state
```

**Issue: Provider authentication fails**

```bash
# Re-login to Azure
az login
az account set --subscription "<subscription-id>"

# Clear Azure CLI cache
rm -rf ~/.azure
az login
```

**Issue: Resource already exists**

```bash
# Import existing resource into state
terraform import <resource_address> <azure_resource_id>

# Or remove from configuration and let Terraform recreate
```

**Issue: State locked**

```bash
# Force unlock (use with caution!)
terraform force-unlock <lock-id>
```

## 📚 Additional Resources

- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure Container Apps Documentation](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [Azure Naming Conventions](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming)

## 🤝 Contributing

### Code Style

```bash
# Format code before committing
terraform fmt -recursive

# Validate before committing
terraform validate
```

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(container-app): add health probe configuration
fix(key-vault): update RBAC permissions
docs(readme): add troubleshooting section
```

---

**Last Updated:** 2026-02-17
**Terraform Version:** >= 1.5.0
**Azure Provider Version:** ~> 3.100
