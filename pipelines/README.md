# Azure DevOps CI/CD Pipelines

CI/CD configuration for the **FinRisk Platform** - Vendor Payment Risk Scoring Integration for FinSure Capital.

---

## Technical Assessment Compliance

### Pipeline Requirements

| Requirement | Status | Implementation |
|-------------|--------|----------------|
| **Stage 1: Build** | | |
| Run tests | ✅ | pytest with coverage |
| Build Docker image | ✅ | Docker buildx (ARM64 → AMD64) |
| Scan image (bonus) | ✅ | Trivy + SBOM generation |
| Push to ACR | ✅ | Semantic versioning from git tags |
| **Stage 2: Infrastructure** | | |
| Terraform init/plan | ✅ | Plan stage with tfsec scan |
| Terraform apply (manual approval for prod) | ✅ | Apply stage with environment approvals |
| **Stage 3: Deploy** | | |
| Deploy container to Azure | ✅ | Azure Container Apps rolling update |
| Smoke test endpoint | ✅ | Health + API validation (`/api/v1/validate`) |
| **Must Demonstrate** | | |
| Use of service connections | ✅ | `azure-service-connection`, `acr-service-connection` |
| Variable groups | ✅ | `finrisk-iac-tf-dev` for state storage |
| Secure secret handling | ✅ | Key Vault + Managed Identity |
| Separate environments (dev/prod) | ✅ | Branch-based targeting |

---

## Pipeline Architecture

```
┌─────────────────────────────────────┐     ┌─────────────────────────────────────┐
│     Infrastructure Pipeline         │     │       Application Pipeline           │
│   (azure-pipelines-infra.yml)       │     │    (azure-pipelines-app.yml)         │
├─────────────────────────────────────┤     ├─────────────────────────────────────┤
│                                     │     │                                     │
│   ┌─────────┐     ┌─────────┐       │     │   ┌─────────┐     ┌─────────┐       │
│   │  Plan   │ ──> │  Apply  │       │     │   │  Build  │ ──> │  Deploy │       │
│   └─────────┘     └─────────┘       │     │   └─────────┘     └─────────┘       │
│       │               │              │     │         │                           │
│       ├── Init        ├── Download   │     │         ▼                           │
│       ├── Validate    ├── Init       │     │   ┌─────────┐                       │
│       ├── tfsec       ├── Apply      │     │   │ Verify  │                       │
│       └── Plan        └── Outputs    │     │   └─────────┘                       │
│                                     │     │                                     │
│   Run this FIRST                    │     │   Run AFTER infrastructure exists   │
│                                     │     │                                     │
│   Triggers: terraform/**            │     │   Triggers: app/**                  │
└─────────────────────────────────────┘     └─────────────────────────────────────┘
```

---

## Branch-Based Environment Targeting

| Branch | Environment | Resources |
|--------|-------------|-----------|
| `dev` | dev | `rg-finrisk-dev`, `ca-finrisk-dev`, `kv-finrisk-dev` |
| `main` | prod | `rg-finrisk-prod`, `ca-finrisk-prod`, `kv-finrisk-prod` |

**Note:** Prod triggers disabled due to Azure subscription quota.

---

## Resources Provisioned

Per Technical Assessment requirements:

| Requirement | Azure Resource |
|-------------|----------------|
| Resource Group | `rg-finrisk-{env}` |
| Azure Container App | `ca-finrisk-{env}` |
| Azure Container Registry | `acrfinrisk{env}` |
| Azure Key Vault | `kv-finrisk-{env}` |
| Log Analytics Workspace | `log-finrisk-{env}` |
| Application Insights | `appi-finrisk-{env}` |
| Managed Identity | System-assigned on Container App |
| Role assignments | AcrPull, Key Vault Secrets User |

### Bonus Security Features

| Feature | Implementation |
|---------|----------------|
| Private endpoints | Key Vault, ACR |
| Azure AD authentication | EasyAuth on Container App |
| Network restrictions | IP allowlist, network ACLs |

---

## Required Azure DevOps Setup

### 1. Service Connections

| Name | Type | Purpose |
|------|------|---------|
| `azure-service-connection` | Azure Resource Manager | Terraform, Azure CLI |
| `acr-service-connection` | Container Registry | Docker push/pull |

### 2. Variable Group

| Name | Variable |
|------|----------|
| `finrisk-iac-tf-dev` | `terraformStateStorageAccount` |

### 3. Environments

| Name | Purpose | Approvals |
|------|---------|-----------|
| `finrisk-iac-tf-dev` | Infra deployment | None (auto) |
| `finrisk-app-dev` | App deployment | None (auto) |

### 4. Install Extensions

- **Terraform** - [Marketplace](https://marketplace.visualstudio.com/items?itemName=ms-devlabs.custom-terraform-tasks)
- **Trivy** (optional) - [Marketplace](https://marketplace.visualstudio.com/items?itemName=AquaSecurityOfficial.trivy-official)

---

## Quick Start

### 1. Bootstrap Infrastructure

```bash
# Create state storage (one-time)
az group create --name rg-terraform-state --location eastus2
STORAGE="stfinrisktf$RANDOM"
az storage account create --name $STORAGE --resource-group rg-terraform-state --sku Standard_LRS
az storage container create --name tfstate --account-name $STORAGE
echo "Storage: $STORAGE"  # Add to variable group
```

### 2. Run Infrastructure Pipeline

```bash
# Push to dev triggers infra pipeline
git push origin dev

# Or manual: Azure DevOps → Pipelines → FinRisk-IaC-Terraform → Run
```

### 3. Run Application Pipeline

```bash
# Push to dev triggers app pipeline
git add app/
git commit -m "feat: update application"
git push origin dev

# Or manual: Azure DevOps → Pipelines → FinRisk-App-CI-CD → Run
```

### 4. Verify Deployment

```bash
# Get app URL
APP_URL=$(az containerapp show --name ca-finrisk-dev --resource-group rg-finrisk-dev --query properties.configuration.ingress.fqdn --output tsv)

# Test health
curl https://$APP_URL/health

# Test API
curl -X POST https://$APP_URL/api/v1/validate \
  -H "Content-Type: application/json" \
  -d '{"firstName":"Jane","lastName":"Doe","idNumber":"9001011234088"}'
```

---

## Local Development

### Terraform

```bash
cd terraform/environments/dev
cp backend.hcl.example backend.hcl
# Edit backend.hcl with storage account

terraform init -backend-config=backend.hcl
terraform validate
terraform plan
terraform apply
```

### Application

```bash
cd app
uv sync --extra dev
uv run pytest --cov=src
uv run ruff check src/
uv run mypy src/

# Build Docker image
docker buildx build --platform linux/amd64 --target production -t applicant-validator:local --load .
docker run -p 8080:8080 applicant-validator:local
curl http://localhost:8080/health
```

---

## Troubleshooting

### "Variable group not found"

1. **Library** → Create variable group `finrisk-iac-tf-dev`
2. Add variable `terraformStateStorageAccount`
3. Authorize pipeline in **Pipeline permissions**

### "Environment not found"

1. **Environments** → Create environment
2. Or wait for auto-create on first run
3. Authorize pipeline when prompted

### "Pipeline doesn't trigger"

1. Verify branch is `dev`
2. Check path matches trigger paths
3. Verify GitHub webhook in Azure DevOps

### Docker Buildx Issues

```bash
# Verify buildx
docker buildx version
docker buildx create --name mybuilder --use
```

### Rollback

```bash
# Manual rollback
az containerapp update --name ca-finrisk-dev --resource-group rg-finrisk-dev \
  --image acrfinriskdev.azurecr.io/applicant-validator:v0.1.0
```

---

## Security Features

### Pipeline Security

| Feature | Tool | Stage |
|---------|------|-------|
| Infrastructure scanning | tfsec | Infra Plan |
| Container scanning | Trivy | App Build |
| Python security | Bandit | App Test |
| Supply chain | SBOM | App Build |

### Runtime Security

| Feature | Implementation |
|---------|----------------|
| Secrets management | Key Vault + Managed Identity |
| Network isolation | Private endpoints (bonus) |
| Authentication | Azure AD EasyAuth (bonus) |
| Access control | RBAC role assignments |

---

## Monitoring

See [MONITORING.md](./MONITORING.md) for:
- Application Insights dashboards
- Log Analytics queries
- Alerting configuration
- Health endpoint monitoring

---

**Last Updated:** 2026-02-18
**Terraform Version:** 1.5.5
**Agent:** Self-hosted macOS with Docker Buildx
**Target:** Azure Container Apps (AMD64)
