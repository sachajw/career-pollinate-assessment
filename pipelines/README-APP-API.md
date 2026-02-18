# Application CI/CD Pipeline

> **Pipeline File:** `azure-pipelines-app.yml`
> **Azure DevOps Name:** `FinRisk-App-CI-CD`
> **Purpose:** Build, test, and deploy the containerized FastAPI application

---

## Technical Assessment Compliance

This pipeline satisfies the following requirements from the Technical Assessment:

### Stage 1: Build ✅

| Requirement | Implementation |
|-------------|----------------|
| Run tests | pytest with coverage reporting |
| Build Docker image | Docker buildx cross-platform (ARM64 → AMD64) |
| Scan image (bonus) | Trivy vulnerability scanner + SBOM generation |
| Push to ACR | Azure Container Registry with semantic versioning |

### Stage 3: Deploy ✅

| Requirement | Implementation |
|-------------|----------------|
| Deploy container to Azure | Azure Container Apps rolling update |
| Smoke test endpoint | Health check + API validation (`/api/v1/validate`) |

### Must Demonstrate ✅

| Requirement | Implementation |
|-------------|----------------|
| Use of service connections | `azure-service-connection`, `acr-service-connection` |
| Variable groups | Not required (all values inline) |
| Secure secret handling | Secrets in Key Vault, accessed via Managed Identity |
| Separate environments (dev/prod) | Branch-based: `dev` → dev, `main` → prod |

---

## Pipeline Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Application Pipeline                          │
│                  (azure-pipelines-app.yml)                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌─────────┐     ┌─────────┐     ┌─────────┐                   │
│   │  Build  │ ──> │  Deploy │ ──> │  Verify  │                  │
│   └─────────┘     └─────────┘     └─────────┘                   │
│       │                                                   │       │
│       ├── Lint (Ruff)                                     │       │
│       ├── Type Check (mypy)                               │       │
│       ├── Security (Bandit)                               │       │
│       ├── Unit Tests (pytest)                             │       │
│       ├── Docker Build (buildx)                           │       │
│       ├── Image Scan (Trivy)                              │       │
│       └── Push to ACR                                     │       │
│                                                                  │
│   Triggered by:                                                  │
│   - Changes to app/**                                            │
│   - Changes to pipelines/azure-pipelines-app.yml                │
│                                                                  │
│   Run AFTER infrastructure exists                                │
└─────────────────────────────────────────────────────────────────┘
```

---

## Stage 1: Build & Test

### Test Job

| Step | Tool | Purpose |
|------|------|---------|
| Lint | Ruff | Code style and quality |
| Type Check | mypy | Static type analysis |
| Security Scan | Bandit | Python security analysis |
| Unit Tests | pytest + coverage | Test execution and coverage |

### BuildImage Job

| Step | Details |
|------|---------|
| Login to ACR | Via service connection |
| Docker buildx | Cross-platform build (ARM64 → AMD64) |
| Push to ACR | Semantic version tag from git |
| Trivy scan | Vulnerability scanning (non-blocking) |
| SBOM | Software Bill of Materials |

### Quality Gates

- All tests must pass
- No type checking errors
- Security issues logged (non-blocking)

---

## Stage 2: Deploy

- Update Container App with new image tag
- Wait 30 seconds for deployment stabilization
- **Deployment Strategy:** Rolling update (zero-downtime)

---

## Stage 3: Verify (Smoke Tests)

| Test | Endpoint | Validation |
|------|----------|------------|
| Health Check | `/health` | HTTP 200, handles cold start |
| Ready Check | `/ready` | HTTP 200 |
| API Validation | `/api/v1/validate` | POST request, verify response schema |

### API Validation Details

```bash
curl -X POST https://$APP_URL/api/v1/validate \
  -H "Content-Type: application/json" \
  -d '{"firstName":"Jane","lastName":"Doe","idNumber":"9001011234088"}'
```

Expected response:
```json
{
  "riskScore": 72,
  "riskLevel": "MEDIUM",
  "correlationId": "abc-123"
}
```

---

## Branch-Based Environment Targeting

| Branch | Environment | Container App | Resource Group |
|--------|-------------|---------------|----------------|
| `dev` | dev | `ca-finrisk-dev` | `rg-finrisk-dev` |
| `main` | prod | `ca-finrisk-prod` | `rg-finrisk-prod` |

**Note:** Prod triggers currently disabled due to Azure subscription quota.

---

## Required Azure DevOps Resources

### Service Connections

| Connection | Type | Purpose |
|------------|------|---------|
| `azure-service-connection` | Azure Resource Manager | Azure CLI operations |
| `acr-service-connection` | Container Registry | Docker push/pull |

### Environments

| Environment | Purpose |
|-------------|---------|
| `finrisk-app-dev` | Dev deployment approvals |
| `finrisk-app-prod` | Prod deployment approvals |

**Note:** No variable groups required - all values are inline.

---

## Local Development

### Test Locally

```bash
cd app

# Run tests
uv sync --extra dev
uv run pytest --cov=src
uv run ruff check src/
uv run mypy src/

# Build Docker image
docker buildx build \
  --platform linux/amd64 \
  --target production \
  -t applicant-validator:local \
  --load .

# Run container
docker run -p 8080:8080 applicant-validator:local
curl http://localhost:8080/health
```

### Push to ACR

```bash
az acr login --name acrfinriskdev

docker buildx build \
  --platform linux/amd64 \
  --target production \
  -t acrfinriskdev.azurecr.io/applicant-validator:test \
  --push .
```

---

## Troubleshooting

### Pipeline Not Triggering

1. Verify branch is `dev` (main disabled)
2. Check path matches `app/**` or pipeline file
3. Verify Azure DevOps webhook connected to GitHub

### Docker Buildx Issues

```bash
# Verify buildx plugin
ls -la ~/.docker/cli-plugins/docker-buildx

# Test buildx
docker buildx version
docker buildx create --name mybuilder --use
```

### Container App Issues

```bash
# Check logs
az containerapp logs show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --follow

# Get app URL
APP_URL=$(az containerapp show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query properties.configuration.ingress.fqdn \
  --output tsv)

# Test endpoint
curl https://$APP_URL/health
```

### Rollback

```bash
# Manual rollback to previous version
az containerapp update \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --image acrfinriskdev.azurecr.io/applicant-validator:v0.1.0
```

---

## Security Features

### Trivy Vulnerability Scanner
- Scans container image for CVEs
- Reports CRITICAL, HIGH, MEDIUM severities
- Non-blocking (informational)

### Bandit
- Python security linting
- Runs during test stage

### SBOM Generation
- Software Bill of Materials
- Supply chain security
- Compliance artifact

---

**Last Updated:** 2026-02-18
**Pipeline:** FinRisk-App-CI-CD
**Agent:** Self-hosted macOS (Apple Silicon) with Docker Buildx
**Target:** Azure Container Apps (AMD64)
