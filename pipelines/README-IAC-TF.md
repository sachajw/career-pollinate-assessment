# Infrastructure as Code Pipeline (FinRisk-IaC-Terraform)

> **Pipeline File:** `azure-pipelines-infra.yml`
> **Azure DevOps Name:** `FinRisk-IaC-Terraform`
> **Purpose:** Provision Azure infrastructure using Terraform

---

## Pipeline Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                   Infrastructure Pipeline                        │
│                (azure-pipelines-infra.yml)                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌─────────┐     ┌─────────┐                                   │
│   │  Plan   │ ──> │  Apply  │                                   │
│   └─────────┘     └─────────┘                                   │
│                                                                  │
│   Triggered by:                                                  │
│   - Changes to terraform/**                                      │
│   - Changes to pipelines/*-infra                                 │
│                                                                  │
│   Run this FIRST (before application pipeline)                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Stage 1: Plan

### TerraformPlan Job

1. **Checkout** - Get source code
2. **Terraform Installer** - Install Terraform 1.7.0
3. **Terraform Init** - Initialize backend and providers
4. **Terraform Validate** - Validate configuration
5. **Terraform Plan** - Generate execution plan
6. **Publish Artifact** - Save plan for Apply stage

### Quality Gates

- Configuration must validate
- Plan must succeed

---

## Stage 2: Apply

### TerraformApply Job (Deployment)

- **Condition:** Only runs on `main` branch
- **Environment:** Requires approval (configurable)

1. **Download Artifact** - Get plan from Plan stage
2. **Terraform Init** - Re-initialize (state lock released between stages)
3. **Terraform Apply** - Execute the saved plan
4. **Save Outputs** - Export Terraform outputs as artifact

---

## Pipeline Variables

```yaml
variables:
  - name: azureSubscription
    value: "azure-service-connection"
  - name: terraformVersion
    value: "1.5.5"

  # Branch-based environment targeting
  - ${{ if eq(variables['Build.SourceBranch'], 'refs/heads/main') }}:
    - name: environmentName
      value: 'prod'
    - name: terraformWorkingDirectory
      value: '$(System.DefaultWorkingDirectory)/terraform/environments/prod'
    - group: finrisk-iac-tf-prod

  - ${{ if eq(variables['Build.SourceBranch'], 'refs/heads/dev') }}:
    - name: environmentName
      value: 'dev'
    - name: terraformWorkingDirectory
      value: '$(System.DefaultWorkingDirectory)/terraform/environments/dev'
    - group: finrisk-iac-tf-dev
```

### Variable Groups

| Variable Group | Environment | Branch |
|----------------|-------------|--------|
| `finrisk-iac-tf-dev` | Development | `dev` |
| `finrisk-iac-tf-prod` | Production | `main` |

### Variable Group Variables

| Variable | Description | Source |
|----------|-------------|--------|
| `terraformStateStorageAccount` | Storage account for Terraform state | Manual setup |

---

## Terraform State Management

### Backend Configuration

Terraform state is stored in Azure Storage Account:

```hcl
# backend.hcl (not checked in)
resource_group_name  = "rg-terraform-state"
storage_account_name = "saterraformstate123"
container_name       = "tfstate"
key                  = "finrisk-dev.tfstate"
```

### State File Security

- State file contains sensitive data (connection strings, keys)
- Stored in Azure Storage with encryption at rest
- Access controlled via Azure RBAC
- **Never commit state files to git**

---

## Setup Instructions

### Prerequisites

1. Azure subscription with Owner access
2. Azure DevOps project with pipeline access
3. Local agent with Terraform installed (or use pipeline installer)

### Step 1: Create Terraform State Storage

```bash
# Create resource group for state
az group create \
  --name rg-terraform-state \
  --location eastus2

# Create storage account
STORAGE_ACCOUNT="saterraformstate$RANDOM"
az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group rg-terraform-state \
  --location eastus2 \
  --sku Standard_LRS \
  --allow-blob-public-access false

# Create container
az storage container create \
  --name tfstate \
  --account-name $STORAGE_ACCOUNT

# Save storage account name for variable group
echo "Storage Account: $STORAGE_ACCOUNT"
```

### Step 2: Create Service Connections

#### Azure Resource Manager Service Connection

```bash
# In Azure DevOps:
# Project Settings > Service connections > New service connection > Azure Resource Manager

# Configuration:
# - Name: azure-service-connection
# - Subscription: Select your subscription
# - Resource Group: Leave empty (subscription-level access)
# - Grant access to all pipelines: Yes
```

### Step 3: Create Variable Groups

```bash
# In Azure DevOps:
# Pipelines > Library > + Variable group

# Create TWO variable groups:

# 1. Variable group name: finrisk-iac-tf-dev
#    Variables:
#    - terraformStateStorageAccount: <storage-account-name-from-step-1>

# 2. Variable group name: finrisk-iac-tf-prod
#    Variables:
#    - terraformStateStorageAccount: <storage-account-name-from-step-1>
```

### Step 4: Create Environments

```bash
# In Azure DevOps:
# Pipelines > Environments > New environment

# Create TWO environments:

# 1. Environment name: dev-infrastructure
#    Description: Development infrastructure deployment
#    Approvers: Optional (auto-deploy)

# 2. Environment name: prod-infrastructure
#    Description: Production infrastructure deployment
#    Approvers: REQUIRED - Add reviewers for production changes
```

### Step 5: Create Pipeline

```bash
# In Azure DevOps:
# Pipelines > New pipeline > Azure Repos Git > Select your repository

# Configure:
# - YAML file path: /pipelines/azure-pipelines-infra.yml
# - Pipeline name in YAML: FinRisk-IaC-Terraform (set via 'name' property)
# - Save (don't run yet)
```

---

## Resources Provisioned

### Core Infrastructure

| Resource | Name | Purpose |
|----------|------|---------|
| Resource Group | `rg-finrisk-dev` | Container for all resources |
| Container Registry | `acrfinriskdev` | Docker image storage |
| Key Vault | `kv-finrisk-dev` | Secrets management |
| Log Analytics | `log-finrisk-dev` | Centralized logging |
| Application Insights | `appi-finrisk-dev` | Application monitoring |

### Container App Infrastructure

| Resource | Name | Purpose |
|----------|------|---------|
| Container App Environment | `cae-finrisk-dev` | Hosting environment |
| Container App | `ca-finrisk-dev` | Application hosting |

### RBAC Assignments

| Principal | Role | Scope |
|-----------|------|-------|
| Container App Identity | AcrPull | Container Registry |
| Container App Identity | Key Vault Secrets User | Key Vault |

---

## Local Development

### Prerequisites

```bash
# Install Terraform
brew install terraform

# Verify installation
terraform --version
# Terraform v1.7.0 or later
```

### Local Terraform Workflow

```bash
cd terraform/environments/dev

# Configure backend (first time only)
cp backend.hcl.example backend.hcl
# Edit backend.hcl with your storage account details

# Configure variables (first time only)
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars as needed

# Initialize
terraform init -backend-config=backend.hcl

# Validate
terraform validate

# Plan
terraform plan -out=tfplan

# Apply (after review)
terraform apply tfplan

# View outputs
terraform output
```

### Using Makefile

```bash
cd terraform/environments/dev

# Check status
make status

# Full workflow
make plan    # Init + validate + plan
make apply   # Plan + apply (with confirmation)

# Other commands
make output  # Show outputs
make clean   # Clean cache
```

---

## Terraform Best Practices

### State Management

1. **Never commit state files** - Use remote backend
2. **Use state locking** - Azure Storage provides this automatically
3. **Backup state** - Azure Storage has built-in backup/restore
4. **Limit state access** - Use Azure RBAC

### Configuration

1. **Use modules** - Organize resources logically
2. **Use variables** - Parameterize for different environments
3. **Use outputs** - Export important values for other systems
4. **Use locals** - Reduce repetition

### Security

1. **Use Managed Identity** - No credentials in code
2. **Use Key Vault** - Store secrets securely
3. **Use RBAC** - Principle of least privilege
4. **Tag resources** - Enable cost tracking and management

---

## Terraform and CI/CD Interaction

### Container Image Management

Container images are **not managed by Terraform**. The CI/CD pipeline handles image updates:

```hcl
# Terraform: Initial deployment uses :latest
container_image = "${module.container_registry.login_server}/applicant-validator:latest"

# CI/CD: Updates with specific versions
az containerapp update --image acrfinriskdev.azurecr.io/applicant-validator:v1.0.0
```

### Drift Prevention

The Terraform module uses `ignore_changes` to prevent drift:

```hcl
lifecycle {
  ignore_changes = [
    template[0].revision_suffix,
    template[0].container[0].image,  # Managed by CI/CD
    ingress[0].transport              # Azure may auto-adjust
  ]
}
```

### Workflow

```
1. Terraform apply → Creates infrastructure with :latest image
2. CI/CD pipeline → Builds and deploys new image versions
3. Terraform plan → No drift detected (ignore_changes)
```

---

## Troubleshooting

### Terraform State Issues

**Issue:** State lock error

```bash
# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

**Issue:** State file corrupted

```bash
# Restore from backup in Azure Portal
# Storage Account > Containers > tfstate > finrisk-dev.tfstate > Versions
```

### Authentication Issues

**Issue:** "subscription not found"

```bash
# Verify Azure CLI is logged in
az account show

# Login if needed
az login

# Set correct subscription
az account set --subscription <subscription-id>
```

### Plan/Apply Issues

**Issue:** Resource already exists

```bash
# Import existing resource
terraform import azurerm_resource_group.this /subscriptions/<id>/resourceGroups/rg-finrisk-dev
```

---

## Pipeline Configuration Reference

### Checkout Settings

```yaml
- checkout: self
  fetchDepth: 1      # Shallow fetch (faster)
  clean: false       # Skip cleanup on local agent
```

### Terraform Tasks

```yaml
- task: TerraformTaskV4@4
  displayName: 'Terraform Init'
  inputs:
    provider: 'azurerm'
    command: 'init'
    workingDirectory: '$(terraformWorkingDirectory)'
    backendServiceArm: '$(azureSubscription)'
    backendAzureRmResourceGroupName: 'rg-terraform-state'
    backendAzureRmStorageAccountName: '$(terraformStateStorageAccount)'
    backendAzureRmContainerName: 'tfstate'
    backendAzureRmKey: 'finrisk-$(environmentName).tfstate'
```

---

## Key Learnings & Best Practices

### Infrastructure Pipeline Design

1. **Separate plan and apply** - Review changes before deployment
2. **Use artifacts** - Pass plans between stages securely
3. **Environment approvals** - Require human approval for production
4. **Limit main branch applies** - Only apply from main branch

### Terraform with Azure DevOps

1. **Use service connections** - Managed identity for authentication
2. **Store state remotely** - Azure Storage with encryption
3. **Use variable groups** - Centralize configuration
4. **Tag all resources** - Enable cost tracking

### Checkout Optimization

```yaml
- checkout: self
  fetchDepth: 1      # Shallow fetch - only latest commit
  clean: false       # Skip post-job cleanup
```

---

**Last Updated:** 2026-02-18
**Pipeline:** FinRisk-IaC-Terraform
**Terraform Version:** 1.5.5
**Backend:** Azure Storage
