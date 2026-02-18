# Infrastructure as Code Pipeline

> **Pipeline File:** `azure-pipelines-infra.yml`
> **Azure DevOps Name:** `FinRisk-IaC-Terraform`
> **Purpose:** Provision Azure infrastructure using Terraform

---

## Technical Assessment Compliance

This pipeline satisfies the following requirements from the Technical Assessment:

### Stage 2: Infrastructure ✅

| Requirement | Implementation |
|-------------|----------------|
| Terraform init/plan | Plan stage with validation and security scan |
| Terraform apply (manual approval for prod) | Apply stage with environment approvals |

### Must Demonstrate ✅

| Requirement | Implementation |
|-------------|----------------|
| Use of service connections | `azure-service-connection` for Azure RM |
| Variable groups | `finrisk-iac-tf-dev` / `finrisk-iac-tf-prod` |
| Secure secret handling | State storage name in variable group, secrets in Key Vault |
| Separate environments (dev/prod) | Branch-based: `dev` → dev, `main` → prod |

### Security Requirements (Pipeline Level) ✅

| Requirement | Implementation |
|-------------|----------------|
| tfsec security scan | Informational scan in Plan stage |
| Diagnostic logging | Enabled via Terraform for all resources |

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
│       │               │                                          │
│       ├── Init        ├── Download plan                          │
│       ├── Validate    ├── Init                                   │
│       ├── tfsec       ├── Apply                                  │
│       ├── Plan        └── Save outputs                           │
│       └── Publish                                                 │
│                                                                  │
│   Triggered by:                                                  │
│   - Changes to terraform/**                                      │
│   - Changes to pipelines/azure-pipelines-infra.yml              │
│                                                                  │
│   Run this FIRST (before application pipeline)                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Stage 1: Plan

| Step | Tool | Purpose |
|------|------|---------|
| Checkout | Git | Get source code |
| Install | TerraformInstaller | Install Terraform 1.5.5 |
| Init | TerraformTaskV4 | Initialize backend and providers |
| Validate | TerraformTaskV4 | Validate configuration |
| Security Scan | tfsec | Static analysis (non-blocking) |
| Plan | TerraformTaskV4 | Generate execution plan |
| Publish | Pipeline Artifact | Save plan for Apply stage |

### Quality Gates

- Configuration must validate
- Plan must succeed
- tfsec results published (informational)

---

## Stage 2: Apply

| Step | Purpose |
|------|---------|
| Download plan | Get saved plan artifact |
| Init | Re-initialize (state lock released between stages) |
| Apply | Execute the saved plan |
| Save outputs | Export Terraform outputs |

### Environment Approvals

| Environment | Branch | Approval |
|-------------|--------|----------|
| `finrisk-iac-tf-dev` | `dev` | None (auto-deploy) |
| `finrisk-iac-tf-prod` | `main` | Required |

---

## Branch-Based Environment Targeting

| Branch | Environment | Working Directory | Variable Group |
|--------|-------------|-------------------|----------------|
| `dev` | dev | `terraform/environments/dev` | `finrisk-iac-tf-dev` |
| `main` | prod | `terraform/environments/prod` | `finrisk-iac-tf-prod` |

**Note:** Prod triggers currently disabled due to Azure subscription quota.

---

## Required Azure DevOps Resources

### Variable Groups

| Variable Group | Required Variable |
|----------------|-------------------|
| `finrisk-iac-tf-dev` | `terraformStateStorageAccount` |
| `finrisk-iac-tf-prod` | `terraformStateStorageAccount` |

### Environments

| Environment | Purpose |
|-------------|---------|
| `finrisk-iac-tf-dev` | Dev infrastructure deployment |
| `finrisk-iac-tf-prod` | Prod infrastructure deployment |

### Service Connections

| Connection | Type | Purpose |
|------------|------|---------|
| `azure-service-connection` | Azure Resource Manager | Terraform operations |

---

## Resources Provisioned

Per Technical Assessment requirements:

| Requirement | Resource | Module |
|-------------|----------|--------|
| Resource Group | `rg-finrisk-{env}` | resource-group |
| Container App | `ca-finrisk-{env}` | container-app |
| Container Registry (ACR) | `acrfinrisk{env}` | container-registry |
| Key Vault | `kv-finrisk-{env}` | key-vault |
| Log Analytics Workspace | `log-finrisk-{env}` | observability |
| Application Insights | `appi-finrisk-{env}` | observability |
| Managed Identity | System-assigned on Container App | container-app |
| Role assignments | AcrPull, Key Vault Secrets User | container-app |

### Bonus Resources

| Resource | Module |
|----------|--------|
| Private endpoints | private-endpoints |
| Azure AD authentication | container-app (EasyAuth) |
| Network restrictions | networking |

---

## Terraform State Management

### Backend Configuration

State stored in Azure Storage (remote backend requirement):

```hcl
# backend.hcl
resource_group_name  = "rg-terraform-state"
storage_account_name = "<from-variable-group>"
container_name       = "tfstate"
key                  = "finrisk-{env}.tfstate"
```

### State Files

| Environment | State File |
|-------------|------------|
| dev | `finrisk-dev.tfstate` |
| prod | `finrisk-prod.tfstate` |

---

## Local Development

### Prerequisites

```bash
brew install terraform
terraform --version  # 1.5.5+
```

### Workflow

```bash
cd terraform/environments/dev

# Configure backend
cp backend.hcl.example backend.hcl
# Edit with your storage account

# Initialize
terraform init -backend-config=backend.hcl

# Validate
terraform validate

# Plan
terraform plan -out=tfplan

# Apply
terraform apply tfplan

# Outputs
terraform output
```

---

## Troubleshooting

### "Variable group not found"

1. Go to **Library** → Verify group exists
2. Check **Pipeline permissions** in the group
3. Add the pipeline if not authorized

### "Environment not found"

1. Go to **Environments** → Create it
2. Or wait - auto-creates on first run
3. Authorize pipeline when prompted

### State Lock Error

```bash
terraform force-unlock <LOCK_ID>
```

### Authentication Issues

```bash
az login
az account set --subscription <subscription-id>
```

### Import Existing Resource

```bash
terraform import azurerm_resource_group.this /subscriptions/<id>/resourceGroups/rg-finrisk-dev
```

---

## Security Features

### tfsec Scanner
- Static analysis of Terraform code
- Runs with `--soft-fail` (non-blocking)
- Results in Tests tab

### Key Vault Integration
- Secrets stored in Key Vault
- Accessed via Managed Identity
- No hardcoded secrets

### Network Security
- Private endpoints (bonus)
- Network ACLs on Key Vault
- IP restrictions on Container App

---

**Last Updated:** 2026-02-18
**Pipeline:** FinRisk-IaC-Terraform
**Terraform Version:** 1.5.5
**Backend:** Azure Storage
