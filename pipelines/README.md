# Azure DevOps CI/CD Pipelines

CI/CD configuration for the **FinRisk Applicant Validator** platform.

---

## Pipeline Architecture

Two separate pipelines for separation of concerns:

```
┌─────────────────────────────────────┐     ┌─────────────────────────────────────┐
│     Infrastructure Pipeline         │     │       Application Pipeline           │
│   (azure-pipelines-infra.yml)       │     │    (azure-pipelines-app.yml)         │
├─────────────────────────────────────┤     ├─────────────────────────────────────┤
│                                     │     │                                     │
│   ┌─────────┐     ┌─────────┐       │     │   ┌─────────┐     ┌─────────┐       │
│   │  Plan   │ ──> │  Apply  │       │     │   │  Build  │ ──> │  Deploy │       │
│   └─────────┘     └─────────┘       │     │   └─────────┘     └─────────┘       │
│                                     │     │         │                           │
│   + tfsec security scan             │     │         ▼                           │
│                                     │     │   ┌─────────┐                       │
│   Run this FIRST                    │     │   │ Verify  │                       │
│                                     │     │   └─────────┘                       │
│   Terraform IaC                     │     │                                     │
│                                     │     │   Run AFTER infrastructure exists   │
└─────────────────────────────────────┘     └─────────────────────────────────────┘
```

---

## Branch-Based Environment Targeting

Both pipelines use the same logic:

| Branch | Environment | Resources |
|--------|-------------|-----------|
| `dev` | dev | `rg-finrisk-dev`, `ca-finrisk-dev` |
| `main` | prod | `rg-finrisk-prod`, `ca-finrisk-prod` |

**Note:** Prod triggers are currently disabled due to Azure subscription quota limits.

---

## Required Azure DevOps Resources

### Variable Groups

| Variable Group | Pipeline | Required Variables |
|----------------|----------|-------------------|
| `finrisk-iac-tf-dev` | Infra | `terraformStateStorageAccount` |

### Environments

| Environment | Pipeline | Purpose |
|-------------|----------|---------|
| `finrisk-iac-tf-dev` | Infra | Dev infrastructure deployment |
| `finrisk-app-dev` | App | Dev application deployment |

**Setup:** Pipelines → Environments → New environment (no checks needed for auto-deploy)

### Service Connections

| Connection | Type | Purpose |
|------------|------|---------|
| `azure-service-connection` | Azure Resource Manager | Terraform operations |
| `acr-service-connection` | Container Registry | Docker push/pull |

---

## Documentation

| Document | Purpose |
|----------|---------|
| [README-APP-API.md](./README-APP-API.md) | Application pipeline details + troubleshooting |
| [README-IAC-TF.md](./README-IAC-TF.md) | Infrastructure pipeline details + troubleshooting |
| [MONITORING.md](./MONITORING.md) | Monitoring and observability guide |

---

## Quick Start

### 1. Infrastructure (Run First)

```bash
# Local validation
cd terraform/environments/dev
terraform init -backend-config=backend.hcl
terraform validate
terraform plan

# Or use Taskfile
task tf:plan
task tf:apply
```

### 2. Application (After Infrastructure)

```bash
# Push to dev branch triggers pipeline
git commit -m "feat: new feature"
git push origin dev

# Pipeline automatically:
# 1. Runs tests (pytest, ruff, mypy, bandit)
# 2. Builds Docker image (AMD64 cross-compile)
# 3. Pushes to ACR
# 4. Deploys to Container App
# 5. Runs smoke tests
```

---

## Triggering Pipelines

### Automatic (Git Push)

```bash
# Infra: changes to terraform/**
git add terraform/
git commit -m "feat: add new resource"
git push origin dev

# App: changes to app/**
git add app/
git commit -m "fix: improve error handling"
git push origin dev
```

### Manual (Azure DevOps UI)

1. Go to **Pipelines** → Select pipeline
2. Click **Run pipeline**
3. Select branch: `dev`
4. Click **Run**

### Pull Request (Plan Only)

PRs run the Plan/Test stage only - no changes are applied.

```bash
git checkout -b feature/my-change
# make changes
git push origin feature/my-change
# Create PR on GitHub
```

---

## Common Issues

### "Variable group not found"

1. Go to **Library** → Verify group exists
2. Check **Pipeline permissions** in the group
3. Add the pipeline if not authorized

### "Environment not found"

1. Go to **Environments** → Create it
2. Or wait - environments auto-create on first run
3. Authorize pipeline when prompted

### "Pipeline doesn't trigger"

1. Verify branch is in trigger list (`dev`)
2. Check path matches trigger paths
3. Verify Azure DevOps webhook is connected to GitHub

### More troubleshooting in pipeline-specific docs:
- [App Pipeline Troubleshooting](./README-APP-API.md#troubleshooting)
- [Infra Pipeline Troubleshooting](./README-IAC-TF.md#troubleshooting)

---

## Technology Stack

| Component | Technology |
|-----------|------------|
| CI/CD | Azure DevOps Pipelines |
| IaC | Terraform 1.5.5 |
| Container Registry | Azure Container Registry |
| Compute | Azure Container Apps |
| Secrets | Azure Key Vault |
| Monitoring | Application Insights + Log Analytics |
| Build | Docker Buildx (cross-platform ARM64 → AMD64) |

---

**Last Updated:** 2026-02-18
**Agent Type:** Self-hosted macOS (Apple Silicon) with Docker Buildx
**Deployment Target:** Azure Container Apps (AMD64)
