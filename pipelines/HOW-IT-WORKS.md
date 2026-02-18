# How the Pipelines Work

This document explains the CI/CD pipeline architecture for the FinRisk Platform.

---

## Overview

The platform uses **two separate pipelines** that work together:

```
┌─────────────────────────────────────────────────────────────────────┐
│                        FinRisk CI/CD Flow                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌──────────────────────┐         ┌──────────────────────┐         │
│   │   Infra Pipeline     │         │    App Pipeline      │         │
│   │ (Terraform IaC)      │         │ (Build & Deploy)     │         │
│   ├──────────────────────┤         ├──────────────────────┤         │
│   │ Trigger:             │         │ Trigger:             │         │
│   │ - terraform/**       │         │ - app/**             │         │
│   │ - pipelines/*-infra  │         │ - pipelines/*-app    │         │
│   ├──────────────────────┤         ├──────────────────────┤         │
│   │ Stages:              │         │ Stages:              │         │
│   │ 1. Plan              │         │ 1. Build & Test      │         │
│   │ 2. Apply             │         │ 2. Deploy            │         │
│   │                      │         │ 3. Verify            │         │
│   └──────────────────────┘         └──────────────────────┘         │
│           │                                  │                       │
│           ▼                                  ▼                       │
│   ┌──────────────────────────────────────────────────────────┐      │
│   │              Azure Infrastructure                         │      │
│   │   Resource Group, Container App, Key Vault, ACR, etc.    │      │
│   └──────────────────────────────────────────────────────────┘      │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Branch-Based Environment Targeting

Both pipelines use the **same branch logic** to determine the target environment:

| Branch | Environment | Variable Group (Infra) | Resources |
|--------|-------------|------------------------|-----------|
| `dev` | dev | `finrisk-iac-tf-dev` | `rg-finrisk-dev`, `ca-finrisk-dev` |
| `main` | prod | `finrisk-iac-tf-prod` | `rg-finrisk-prod`, `ca-finrisk-prod` |
| PRs/other | dev | `finrisk-iac-tf-dev` | Same as dev |

**Implementation:**
```yaml
variables:
  - ${{ if eq(variables['Build.SourceBranch'], 'refs/heads/main') }}:
    - name: environmentName
      value: 'prod'
    - group: finrisk-iac-tf-prod

  - ${{ if eq(variables['Build.SourceBranch'], 'refs/heads/dev') }}:
    - name: environmentName
      value: 'dev'
    - group: finrisk-iac-tf-dev
```

---

## Pipeline Triggers

### Infrastructure Pipeline (`azure-pipelines-infra.yml`)

```yaml
trigger:
  branches:
    include:
      - dev        # Only dev branch (prod disabled due to quota)
  paths:
    include:
      - terraform/**
      - pipelines/azure-pipelines-infra.yml
```

**When it runs:**
- Push to `dev` branch that changes Terraform files
- Push to the pipeline file itself

### Application Pipeline (`azure-pipelines-app.yml`)

```yaml
trigger:
  branches:
    include:
      - dev        # Only dev branch (prod disabled due to quota)
  paths:
    include:
      - app/**
      - pipelines/azure-pipelines-app.yml
```

**When it runs:**
- Push to `dev` branch that changes application code
- Push to the pipeline file itself

---

## Infrastructure Pipeline Stages

### Stage 1: Plan

```
┌─────────────────────────────────────────────────────────┐
│                    Terraform Plan                        │
├─────────────────────────────────────────────────────────┤
│  1. Checkout code                                        │
│  2. Install Terraform 1.5.5                              │
│  3. Terraform Init (remote backend)                      │
│  4. Terraform Validate                                   │
│  5. tfsec Security Scan (informational)                  │
│  6. Terraform Plan (-out=tfplan)                         │
│  7. Publish tfplan artifact                              │
└─────────────────────────────────────────────────────────┘
```

**Key Points:**
- Uses Azure Storage backend for state
- State file: `finrisk-{environment}.tfstate`
- tfsec runs with `--soft-fail` (non-blocking)

### Stage 2: Apply

```
┌─────────────────────────────────────────────────────────┐
│                   Terraform Apply                        │
├─────────────────────────────────────────────────────────┤
│  1. Download tfplan artifact                             │
│  2. Terraform Init                                       │
│  3. Terraform Apply (uses saved plan)                    │
│  4. Save outputs to artifact                             │
└─────────────────────────────────────────────────────────┘
```

**Key Points:**
- Uses **deployment job** for environment approvals
- Environment: `finrisk-iac-tf-{environmentName}`
- Plan is passed as artifact (ensures same plan is applied)

---

## Application Pipeline Stages

### Stage 1: Build & Test

```
┌─────────────────────────────────────────────────────────┐
│                    Build & Test                          │
├─────────────────────────────────────────────────────────┤
│  Test Job:                                               │
│  - Install Python 3.13 + uv                              │
│  - Lint (Ruff)                                           │
│  - Type check (mypy)                                     │
│  - Security scan (Bandit)                                │
│  - Unit tests (pytest + coverage)                        │
│                                                          │
│  BuildImage Job:                                         │
│  - Login to ACR                                          │
│  - Docker buildx build (AMD64 cross-compile)             │
│  - Push to ACR with version tag                          │
│  - Trivy vulnerability scan (non-blocking)               │
│  - Generate SBOM                                         │
└─────────────────────────────────────────────────────────┘
```

**Key Points:**
- Cross-platform build: ARM64 Mac → AMD64 Azure
- Version from `git describe --tags`
- Trivy is informational (doesn't block deploy)

### Stage 2: Deploy

```
┌─────────────────────────────────────────────────────────┐
│                      Deploy                              │
├─────────────────────────────────────────────────────────┤
│  1. Update Container App with new image                  │
│  2. Wait 30 seconds for rollout                          │
└─────────────────────────────────────────────────────────┘
```

**Key Points:**
- Uses **deployment job** for environment approvals
- Environment: `finrisk-app-{environmentName}`
- Rolling update (zero-downtime)

### Stage 3: Verify

```
┌─────────────────────────────────────────────────────────┐
│                      Verify                              │
├─────────────────────────────────────────────────────────┤
│  1. Health check (/health) - 10 retries                 │
│  2. Ready check (/ready)                                 │
│  3. API validation (POST /api/v1/validate)              │
│  4. Verify response structure                            │
└─────────────────────────────────────────────────────────┘
```

**Key Points:**
- Handles cold start (scale-to-zero)
- Tests actual business logic
- Fails pipeline if API doesn't work

---

## Azure DevOps Resources Required

### Variable Groups

| Variable Group | Pipeline | Required Variables |
|----------------|----------|-------------------|
| `finrisk-iac-tf-dev` | Infra | `terraformStateStorageAccount` |
| `finrisk-iac-tf-prod` | Infra | `terraformStateStorageAccount` |

**Note:** The app pipeline doesn't need variable groups - all values are inline.

### Environments

| Environment | Pipeline | Purpose |
|-------------|----------|---------|
| `finrisk-iac-tf-dev` | Infra | Dev infrastructure deployment |
| `finrisk-iac-tf-prod` | Infra | Prod infrastructure deployment |
| `finrisk-app-dev` | App | Dev app deployment |
| `finrisk-app-prod` | App | Prod app deployment |

**Setup:**
1. Go to **Pipelines** → **Environments**
2. Create each environment
3. For dev: No approvals (auto-deploy)
4. For prod: Add approvers

### Service Connections

| Connection | Type | Purpose |
|------------|------|---------|
| `azure-service-connection` | Azure Resource Manager | Terraform operations |
| `acr-service-connection` | Container Registry | Docker push/pull |

---

## State Management

Terraform state is stored in Azure Storage:

```
Storage Account: saterraformstateXXX
Container: tfstate
├── finrisk-dev.tfstate     # Dev environment state
└── finrisk-prod.tfstate    # Prod environment state
```

**State file per environment** ensures isolation.

---

## Security Features

### tfsec (Infrastructure Pipeline)
- Static analysis of Terraform code
- Runs with `--soft-fail` (informational only)
- Results published to Tests tab

### Trivy (Application Pipeline)
- Container image vulnerability scanning
- Scans for CRITICAL, HIGH, MEDIUM severities
- Non-blocking (`exit-code: 0`)

### Bandit (Application Pipeline)
- Python code security analysis
- Runs during test stage

---

## Typical Workflow

### Infrastructure Change

```bash
# 1. Make changes to Terraform
vim terraform/modules/key-vault/main.tf

# 2. Commit and push to dev
git add .
git commit -m "feat: add network ACLs to Key Vault"
git push origin dev

# 3. Pipeline automatically runs:
#    - Plan stage shows changes
#    - Apply stage deploys to dev

# 4. Verify in Azure Portal
```

### Application Change

```bash
# 1. Make changes to app code
vim app/src/services/riskshield.py

# 2. Commit and push to dev
git add .
git commit -m "fix: improve retry logic"
git push origin dev

# 3. Pipeline automatically runs:
#    - Tests run
#    - Image builds and pushes to ACR
#    - Container App updates
#    - Smoke tests verify deployment

# 4. Check app is working
curl https://ca-finrisk-dev.azurecontainerapps.io/health
```

---

## Troubleshooting

### Pipeline Not Triggering

1. Check the trigger paths match your changes
2. Verify you're pushing to `dev` branch
3. Check pipeline file isn't excluded

### "Variable group not found"

1. Go to **Library** and verify group exists
2. Check exact name matches pipeline reference
3. Authorize pipeline in group's **Pipeline permissions**

### "Environment not found"

1. Go to **Environments** and create it
2. Authorize pipeline in environment's **Security**

### Terraform State Lock

```bash
# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

### Container App Not Updating

1. Check ACR push succeeded
2. Verify image tag is correct
3. Check Container App logs:
   ```bash
   az containerapp logs show --name ca-finrisk-dev --resource-group rg-finrisk-dev
   ```

---

## File Structure

```
pipelines/
├── azure-pipelines-app.yml      # Application CI/CD
├── azure-pipelines-infra.yml    # Infrastructure CI/CD
├── HOW-IT-WORKS.md              # This document
├── README.md                    # Pipeline overview
├── README-APP-API.md            # App pipeline details
├── README-IAC-TF.md             # Infra pipeline details
├── TROUBLESHOOTING.md           # Common issues
└── MONITORING.md                # Monitoring guide
```

---

**Last Updated:** 2026-02-18
