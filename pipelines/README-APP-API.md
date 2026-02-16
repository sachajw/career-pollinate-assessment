# Application CI/CD Pipeline (FinRisk-App-CI-CD)

> **Pipeline File:** `azure-pipelines-app.yml`
> **Azure DevOps Name:** `FinRisk-App-CI-CD`
> **Purpose:** Build, test, and deploy the containerized FastAPI application

---

## Pipeline Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Application Pipeline                          │
│                  (azure-pipelines-app.yml)                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌─────────┐     ┌─────────┐     ┌─────────┐                   │
│   │  Build  │ ──> │  Deploy │ ──> │ Verify  │                   │
│   └─────────┘     └─────────┘     └─────────┘                   │
│                                                                  │
│   Triggered by:                                                  │
│   - Changes to app/**                                            │
│   - Changes to pipelines/*-app                                   │
│                                                                  │
│   Run AFTER infrastructure exists                                │
└─────────────────────────────────────────────────────────────────┘
```

---

## Stage 1: Build & Test

### Test Job (Unit Tests & Quality Checks)

- Setup Python 3.13 with uv package manager
- Install dependencies (`uv sync --extra dev`)
- **Lint** with Ruff
- **Type check** with mypy
- **Security scan** with Bandit
- **Run unit tests** with pytest (coverage report)
- Publish test results and code coverage

### BuildImage Job (Cross-Platform Docker Build)

- **Setup PATH** for OrbStack Docker (buildx-capable)
- **Login to ACR** (Azure Container Registry)
- **Setup Docker buildx** for cross-platform builds
- **Build AMD64 image** (cross-compile from ARM64 Mac to x86_64 Azure)
- **Push to ACR** with semantic version tag (from git describe) + latest
- **Scan image** with Trivy (security vulnerabilities)

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

## Stage 3: Verify (Enhanced Smoke Tests)

### Health Check (`/health`)
- 10 retry attempts with 10s intervals
- Handles cold start (scale-to-zero) and rollout delays

### Endpoint Checks
- OpenAPI docs (`/docs`)
- Readiness probe (`/ready`)

### Validate API Test (`/api/v1/validate`)
- **Business logic verification**
- POST request with sample data
- Validates HTTP 200 response
- Checks all required fields (riskScore, riskLevel, correlationId)
- Verifies riskLevel enum (LOW, MEDIUM, HIGH)

---

## Semantic Versioning

Image tags are derived from **git tags** using `git describe --tags`. Git is the source of truth for versions.

**Format:** `v{major}.{minor}.{patch}-{commits}-g{hash}`

| Scenario | Git Tag | Commits Since | Image Tag |
|----------|---------|---------------|-----------|
| Release | `v1.0.0` | 0 | `v1.0.0` |
| Post-release dev | `v1.0.0` | 5 | `v1.0.0-5-gabc123` |
| No tags yet | (none) | - | `v0.0.0-abc123` |

### Creating a Release

```bash
git tag v1.0.0
git push origin v1.0.0
# Pipeline will build image: applicant-validator:v1.0.0
```

### Pipeline Step

```yaml
- script: |
    VERSION=$(git describe --tags --always --dirty 2>/dev/null || echo "v0.0.0-$(git rev-parse --short HEAD)")
    echo "##vso[task.setvariable variable=imageTag]$VERSION"
  displayName: 'Set Version from Git'
```

---

## Pipeline Variables

```yaml
variables:
  - group: finrisk-dev
  - name: azureSubscription
    value: "azure-service-connection"
  - name: environmentName
    value: "dev"
  - name: pythonVersion
    value: "3.13"
  - name: dockerRegistryServiceConnection
    value: "acr-service-connection"
  - name: containerRegistry
    value: "acrfinriskdev.azurecr.io"
  - name: imageName
    value: "applicant-validator"
  # imageTag: Set dynamically from git describe --tags
  - name: containerAppName
    value: "ca-finrisk-dev"
  - name: resourceGroupName
    value: "rg-finrisk-dev"
```

---

## Local Agent Setup (macOS with Docker Buildx)

### Why Docker Buildx?

The application must run on **Azure Container Apps (AMD64/x86_64)**, but development happens on **Apple Silicon Macs (ARM64)**. Docker buildx enables **cross-platform builds** without emulation.

### Prerequisites

1. **macOS with Apple Silicon** (M1/M2/M3)
2. **OrbStack** (provides Docker with buildx) - `brew install orbstack`
3. **Azure DevOps Account** with agent pool access
4. **Azure Subscription** with Container Apps access

### Step 1: Install Azure Pipelines Agent

```bash
mkdir -p ~/azure-pipelines-agent
cd ~/azure-pipelines-agent

curl -O https://vstsagentpackage.azureedge.net/agent/3.236.1/vsts-agent-osx-arm64-3.236.1.tar.gz
tar zxvf vsts-agent-osx-arm64-3.236.1.tar.gz
./config.sh

# When prompted:
# - Server URL: https://dev.azure.com/{your-org}
# - Authentication: PAT
# - Agent pool: Default
# - Agent name: local-mac
```

### Step 2: Verify Docker Buildx

```bash
docker --version
docker buildx version
docker buildx ls

# Create builder if not exists
docker buildx create --name mybuilder --use
docker buildx inspect --bootstrap
```

### Step 3: Run the Agent

```bash
cd ~/azure-pipelines-agent

# Interactive mode (for testing)
./run.sh

# OR run as background service (recommended)
./svc.sh install
./svc.sh start
./svc.sh status
```

---

## Docker Buildx Configuration in Pipeline

### Critical Environment Variables

```yaml
- script: |
    DOCKER=/Users/tvl/.orbstack/bin/docker
    export DOCKER_CONFIG=/Users/tvl/.docker
    export HOME=/Users/tvl

    $DOCKER buildx version

    $DOCKER buildx build \
      --platform linux/amd64 \
      --target production \
      -t $(containerRegistry)/$(imageName):$(imageTag) \
      --push \
      .
  displayName: "Build and Push Docker Image (AMD64)"
```

### Why This Configuration?

| Setting | Purpose |
|---------|---------|
| `DOCKER=/Users/tvl/.orbstack/bin/docker` | Ensures buildx-capable Docker is used |
| `DOCKER_CONFIG=/Users/tvl/.docker` | Points to directory containing `cli-plugins/docker-buildx` |
| `HOME=/Users/tvl` | Ensures Docker looks in correct home directory |
| `--platform linux/amd64` | Cross-compiles from ARM64 (Mac) to AMD64 (Azure) |

---

## Testing Locally

### Test Application Build (with buildx)

```bash
cd app

docker buildx build \
  --platform linux/amd64 \
  --target production \
  -t applicant-validator:local \
  --load \
  .

# Verify image architecture
docker inspect applicant-validator:local | grep Architecture
# Should show: "Architecture": "amd64"

# Run and test
docker run -p 8080:8080 applicant-validator:local
curl http://localhost:8080/health
```

### Test Build and Push to ACR

```bash
az acr login --name acrfinriskdev

cd app
docker buildx build \
  --platform linux/amd64 \
  --target production \
  -t acrfinriskdev.azurecr.io/applicant-validator:test \
  --push \
  .
```

### Test Python Steps Locally

```bash
cd app
uv sync --extra dev
uv run pytest --cov=src --cov-report=html
uv run ruff check src/
uv run mypy src/
uv run bandit -r src/ -c pyproject.toml
```

---

## Troubleshooting

### Docker Buildx Issues

**Issue:** `docker: unknown command: docker buildx`

```bash
# Verify buildx plugin exists
ls -la ~/.docker/cli-plugins/docker-buildx

# Ensure pipeline sets DOCKER_CONFIG
export DOCKER_CONFIG=/Users/$(whoami)/.docker
export HOME=/Users/$(whoami)
docker buildx version
```

**Issue:** `unknown flag: --platform`

```bash
# Use explicit path to OrbStack Docker
DOCKER=/Users/tvl/.orbstack/bin/docker
$DOCKER buildx version
```

### Container App Deployment Issues

```bash
# Check logs
az containerapp logs show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --follow

# Test endpoints manually
APP_URL=$(az containerapp show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query properties.configuration.ingress.fqdn \
  --output tsv)

curl https://$APP_URL/health
curl -X POST https://$APP_URL/api/v1/validate \
  -H "Content-Type: application/json" \
  -d '{"firstName":"Test","lastName":"User","idNumber":"9001011234088"}'
```

---

## CI/CD Workflow

### Development Workflow

```bash
# 1. Make code changes
cd app/src

# 2. Test locally
cd ../
uv run pytest
uv run ruff check src/

# 3. Commit and push
git add .
git commit -m "feat: add new validation rule"
git push origin main

# 4. Pipeline automatically:
#    - Runs tests (~2 min)
#    - Builds AMD64 image with buildx (~1 min)
#    - Pushes to ACR
#    - Deploys to Container App (~1 min)
#    - Runs smoke tests (~30 sec)
#    Total: ~4-5 minutes
```

### Rollback Procedure

```bash
# Option 1: Rerun previous successful build in Azure DevOps

# Option 2: Manual rollback via Azure CLI
az containerapp update \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --image acrfinriskdev.azurecr.io/applicant-validator:v0.1.0
```

---

## Key Learnings & Best Practices

### Docker Buildx on Local Agents

1. Use explicit paths - Don't rely on PATH for Docker binary
2. Set DOCKER_CONFIG and HOME - Required for plugin discovery
3. Create dedicated builder - `docker buildx create --name mybuilder --use`
4. Bootstrap before use - `docker buildx inspect --bootstrap`
5. Test locally first - Verify buildx works before pipeline

### Pipeline Design

1. Comprehensive smoke tests - Test business logic, not just health checks
2. Fast feedback - Keep builds under 5 minutes
3. Explicit configuration - Don't rely on agent defaults
4. Proper error handling - Use `set -e` and validate each step

### Checkout Optimization (Local Agents)

```yaml
- checkout: self
  fetchDepth: 0      # Full history needed for git describe
  clean: false       # Skip post-job cleanup
```

### Cross-Platform Builds

1. Always specify platform - `--platform linux/amd64`
2. Use production target - `--target production`
3. Push directly - `--push` (don't use `--load` for cross-platform)
4. Verify architecture - Check `docker inspect` shows correct arch

---

**Last Updated:** 2026-02-16
**Pipeline:** FinRisk-App-CI-CD
**Agent Type:** Self-hosted macOS (Apple Silicon) with Docker Buildx
**Deployment Target:** Azure Container Apps (AMD64)
