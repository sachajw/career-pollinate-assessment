[![Build Status](https://dev.azure.com/pangarabbit/finrisk/_apis/build/status%2Fsachajw.career-pollinate-assessment%20(2)?branchName=main)](https://dev.azure.com/pangarabbit/finrisk/_build/latest?definitionId=2&branchName=main)

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
│   Run this FIRST                    │     │         ▼                           │
│                                     │     │   ┌─────────┐                       │
│   Terraform IaC                     │     │   │ Verify  │                       │
│                                     │     │   └─────────┘                       │
│                                     │     │                                     │
│                                     │     │   Run AFTER infrastructure exists   │
│                                     │     │                                     │
│                                     │     │   Docker Buildx CI/CD               │
└─────────────────────────────────────┘     └─────────────────────────────────────┘
```

---

## Documentation

| Document | Purpose |
|----------|---------|
| [README-APP-API.md](./README-APP-API.md) | Application CI/CD pipeline (Docker, buildx, deployments) |
| [README-IAC-TF.md](./README-IAC-TF.md) | Infrastructure pipeline (Terraform, state management) |

---

## Pipeline Files

| File | Azure DevOps Name | Purpose |
|------|-------------------|---------|
| `azure-pipelines-infra.yml` | `FinRisk-IaC-Terraform` | Terraform infrastructure provisioning |
| `azure-pipelines-app.yml` | `FinRisk-App-CI-CD` | Application build, test, deploy, verify |

---

## Quick Start

### 1. Infrastructure (Run First)

```bash
# See README-IAC-TF.md for full setup
cd terraform/environments/dev
make plan
make apply
```

### 2. Application (After Infrastructure)

```bash
# See README-APP-API.md for full setup
git tag v0.1.0
git push origin v0.1.0
# Pipeline automatically builds, deploys, and verifies
```

---

## Workflow Summary

```bash
# Infrastructure change
cd terraform/environments/dev
make plan && make apply

# Application change
git commit -m "feat: new feature"
git push  # → v0.1.0-1-gabc123

# Release
git tag v1.0.0
git push origin v1.0.0  # → v1.0.0
```

---

## Technology Stack

| Component | Technology |
|-----------|------------|
| CI/CD | Azure DevOps Pipelines |
| IaC | Terraform 1.7.0 |
| Container Registry | Azure Container Registry |
| Compute | Azure Container Apps |
| Secrets | Azure Key Vault |
| Monitoring | Application Insights + Log Analytics |
| Build | Docker Buildx (cross-platform ARM64 → AMD64) |

---

**Last Updated:** 2026-02-16
**Agent Type:** Self-hosted macOS (Apple Silicon) with Docker Buildx
**Deployment Target:** Azure Container Apps (AMD64)
