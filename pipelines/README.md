# Azure DevOps CI/CD Pipelines

This directory contains the CI/CD pipeline configuration for the **FinRisk Applicant Validator** platform.

## 📋 Pipeline Architecture

The CI/CD is split into **two separate pipelines** for better separation of concerns:

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
│   Triggered by:                     │     │         ▼                           │
│   - Changes to terraform/**         │     │   ┌─────────┐                       │
│   - Changes to pipelines/*-infra    │     │   │ Verify  │                       │
│                                     │     │   └─────────┘                       │
│   Run this FIRST                    │     │                                     │
│                                     │     │   Triggered by:                     │
│                                     │     │   - Changes to app/**               │
│                                     │     │   - Changes to pipelines/*-app      │
│                                     │     │                                     │
│                                     │     │   Run AFTER infrastructure exists   │
└─────────────────────────────────────┘     └─────────────────────────────────────┘
```

---

## Application Pipeline (`azure-pipelines-app.yml`)

**Purpose:** Build, test, and deploy the containerized FastAPI application with cross-platform Docker buildx support.

### Stage 1: Build & Test

**Jobs:**

1. **Test Job** (Unit Tests & Quality Checks)
   - Setup Python 3.13 with uv package manager
   - Install dependencies (`uv sync --extra dev`)
   - **Lint** with Ruff
   - **Type check** with mypy
   - **Security scan** with Bandit
   - **Run unit tests** with pytest (coverage report)
   - Publish test results and code coverage

2. **BuildImage Job** (Cross-Platform Docker Build)
   - **Setup PATH** for OrbStack Docker (buildx-capable)
   - **Login to ACR** (Azure Container Registry)
   - **Setup Docker buildx** for cross-platform builds
   - **Build AMD64 image** (cross-compile from ARM64 Mac to x86_64 Azure)
   - **Push to ACR** with Build.BuildId tag + latest
   - **Scan image** with Trivy (security vulnerabilities)

**Quality Gates:**
- ✅ All tests must pass
- ✅ No type checking errors
- ⚠️ Security issues logged (continueOnError: true)

### Stage 2: Deploy

**Steps:**
- Update Container App with new image tag
- Wait 30 seconds for deployment stabilization

**Deployment Strategy:** Rolling update (zero-downtime)

### Stage 3: Verify (Enhanced Smoke Tests)

**Comprehensive End-to-End Verification:**

1. **Health Check** (`/health`)
   - 10 retry attempts with 10s intervals
   - Ensures container is running

2. **Endpoint Checks**
   - OpenAPI docs (`/docs`)
   - Readiness probe (`/ready`)

3. **🆕 Validate API Test** (`/api/v1/validate`)
   - **Business logic verification**
   - POST request with sample data
   - Validates HTTP 200 response
   - Checks all required fields (riskScore, riskLevel, correlationId)
   - Verifies riskLevel enum (LOW, MEDIUM, HIGH)
   - Displays actual response values

**Rollback:** Manual rollback via Azure Portal or rerun previous build if smoke tests fail

**Trigger:** Changes to `app/**` directory

---

## 🖥️ Local Agent Setup (macOS with Docker Buildx)

### Why Docker Buildx?

The application must run on **Azure Container Apps (AMD64/x86_64)**, but development happens on **Apple Silicon Macs (ARM64)**. Docker buildx enables **cross-platform builds** without emulation.

### Prerequisites

1. **macOS with Apple Silicon** (M1/M2/M3)
2. **OrbStack** (provides Docker with buildx) - `brew install orbstack`
3. **Azure DevOps Account** with agent pool access
4. **Azure Subscription** with Container Apps access

### Step 1: Install Azure Pipelines Agent

```bash
# Create agent directory
mkdir -p ~/azure-pipelines-agent
cd ~/azure-pipelines-agent

# Download agent (replace with latest version)
curl -O https://vstsagentpackage.azureedge.net/agent/3.236.1/vsts-agent-osx-arm64-3.236.1.tar.gz

# Extract
tar zxvf vsts-agent-osx-arm64-3.236.1.tar.gz

# Configure agent
./config.sh

# When prompted:
# - Server URL: https://dev.azure.com/{your-org}
# - Authentication: PAT (Personal Access Token)
# - Agent pool: Default (or custom pool)
# - Agent name: local-mac (or custom name)
# - Work folder: _work (default)
```

### Step 2: Verify Docker Buildx

```bash
# Check Docker installation
docker --version
# Docker version 28.5.2, build ecc6942

# Check buildx plugin
docker buildx version
# github.com/docker/buildx v0.29.1 a32761aeb3debd39be1eca514af3693af0db334b

# List buildx builders
docker buildx ls
# NAME/NODE    DRIVER/ENDPOINT  STATUS   BUILDKIT  PLATFORMS
# mybuilder *  docker-container running  v0.27.1   linux/arm64, linux/amd64, ...

# Create buildx builder if not exists
docker buildx create --name mybuilder --use
docker buildx inspect --bootstrap
```

### Step 3: Configure Agent Environment

The agent needs to find Docker and the buildx plugin:

```bash
cd ~/azure-pipelines-agent

# Create/edit .path file (agent uses this for PATH)
# Note: This file is loaded during agent startup but NOT during task execution
echo "/Users/$(whoami)/.orbstack/bin" > .path
cat ~/.zshrc | grep PATH >> .path  # Optional: add your shell PATH
```

**⚠️ Important:** The `.path` file is only used for agent capability scanning. Task execution requires explicit configuration in the pipeline YAML (see below).

### Step 4: Run the Agent

```bash
cd ~/azure-pipelines-agent

# Interactive mode (for testing)
./run.sh

# OR run as background service (recommended)
./svc.sh install  # Install as launchd service
./svc.sh start    # Start service
./svc.sh status   # Check status
```

### Step 5: Verify Agent Registration

```bash
# In Azure DevOps:
# Project Settings > Agent pools > Default > Agents
# Your agent should appear as "Online"

# Check agent capabilities (should include docker and buildx)
```

---

## 🐳 Docker Buildx Configuration in Pipeline

### Critical Environment Variables

The pipeline **must** set these environment variables for Docker to find the buildx plugin:

```yaml
- script: |
    # Use OrbStack Docker explicitly
    DOCKER=/Users/tvl/.orbstack/bin/docker

    # CRITICAL: These allow Docker to find CLI plugins
    export DOCKER_CONFIG=/Users/tvl/.docker
    export HOME=/Users/tvl

    # Verify buildx is available
    $DOCKER buildx version

    # Build cross-platform image
    $DOCKER buildx build \
      --platform linux/amd64 \
      --target production \
      -t $(containerRegistry)/$(imageName):$(imageTag) \
      --push \
      .
  displayName: 'Build and Push Docker Image (AMD64)'
```

### Why This Configuration?

1. **Explicit Docker Path**: `DOCKER=/Users/tvl/.orbstack/bin/docker`
   - Ensures buildx-capable Docker is used
   - `##vso[task.prependpath]` doesn't persist across script tasks

2. **DOCKER_CONFIG=/Users/tvl/.docker**
   - Points to directory containing `cli-plugins/docker-buildx`
   - Without this, Docker can't find buildx plugin

3. **HOME=/Users/tvl**
   - Ensures Docker looks in correct home directory
   - Agent tasks run with different HOME by default

4. **--platform linux/amd64**
   - Cross-compiles from ARM64 (Mac) to AMD64 (Azure)
   - Buildx uses QEMU emulation for cross-platform builds

---

## 🚀 Setup Instructions

### Step 1: Create Service Connections

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

#### Azure Container Registry Service Connection

```bash
# In Azure DevOps:
# Project Settings > Service connections > New service connection > Docker Registry

# Configuration:
# - Registry type: Azure Container Registry
# - Subscription: Select your subscription
# - Azure Container Registry: acrfinriskdev (created by Terraform)
# - Service connection name: acr-service-connection
# - Grant access to all pipelines: Yes
```

### Step 2: Create Variable Group

```bash
# In Azure DevOps:
# Pipelines > Library > + Variable group

# Variable group name: finrisk-dev

# Variables (all populated by Terraform outputs):
# - None required initially - pipeline uses hardcoded naming convention
```

### Step 3: Create Application Pipeline

```bash
# In Azure DevOps:
# Pipelines > New pipeline > Azure Repos Git > Select your repository

# Configure:
# - Pipeline name: FinRisk-Application
# - YAML file path: /pipelines/azure-pipelines-app.yml
# - Save and run
```

### Step 4: Create Environment

```bash
# In Azure DevOps:
# Pipelines > Environments > New environment

# Environment name: dev
# Description: Development environment
# Add approvers: Optional for dev
```

---

## 📝 Pipeline Variables

### Application Pipeline Configuration

```yaml
variables:
  - group: finrisk-dev
  - name: azureSubscription
    value: 'azure-service-connection'
  - name: environmentName
    value: 'dev'
  - name: pythonVersion
    value: '3.13'
  - name: dockerRegistryServiceConnection
    value: 'acr-service-connection'
  - name: containerRegistry
    value: 'acrfinriskdev.azurecr.io'      # Matches Terraform output
  - name: imageName
    value: 'applicant-validator'            # Domain service name (DDD)
  - name: imageTag
    value: '$(Build.BuildId)'               # Unique per build
  - name: containerAppName
    value: 'ca-finrisk-dev'                 # Matches Terraform resource name
  - name: resourceGroupName
    value: 'rg-finrisk-dev'                 # Matches Terraform resource group
```

### Naming Convention (DDD-Aligned)

| Resource | Format | Dev Value | Source |
|----------|--------|-----------|--------|
| Resource Group | `rg-{project}-{env}` | `rg-finrisk-dev` | Terraform |
| Container App | `ca-{project}-{env}` | `ca-finrisk-dev` | Terraform |
| Container Registry | `acr{project}{env}` | `acrfinriskdev` | Terraform |
| Container Image | Domain service name | `applicant-validator` | Domain model |

**DDD Naming:**
- `finrisk` = **FinSure** + **Risk** validation bounded context
- `applicant-validator` = Domain service performing fraud risk validation

---

## 🧪 Testing Locally

### Test Application Build (with buildx)

```bash
cd app

# Test cross-platform build locally
docker buildx build \
  --platform linux/amd64 \
  --target production \
  -t applicant-validator:local \
  --load \
  .

# Verify image architecture
docker inspect applicant-validator:local | grep Architecture
# Should show: "Architecture": "amd64"

# Run container and test
docker run -p 8080:8080 applicant-validator:local

# Test endpoints
curl http://localhost:8080/health
curl http://localhost:8080/ready
curl -X POST http://localhost:8080/api/v1/validate \
  -H "Content-Type: application/json" \
  -d '{"firstName":"Jane","lastName":"Doe","idNumber":"9001011234088"}'
```

### Test Application Build and Push to ACR

```bash
# Login to ACR
az acr login --name acrfinriskdev

# Build and push (same as pipeline)
cd app
docker buildx build \
  --platform linux/amd64 \
  --target production \
  -t acrfinriskdev.azurecr.io/applicant-validator:test \
  --push \
  .

# Verify image in ACR
az acr repository show-tags \
  --name acrfinriskdev \
  --repository applicant-validator \
  --output table
```

### Test Python Steps Locally

```bash
cd app

# Install dependencies
uv sync --extra dev

# Run tests
uv run pytest --cov=src --cov-report=html

# Lint
uv run ruff check src/

# Type check
uv run mypy src/

# Security scan
uv run bandit -r src/ -c pyproject.toml
```

---

## 🚨 Troubleshooting

### Docker Buildx Issues

**Issue:** `docker: unknown command: docker buildx`

```bash
# Solution: Buildx plugin not found by Docker

# 1. Verify buildx plugin exists
ls -la ~/.docker/cli-plugins/docker-buildx

# 2. Check if symlink is correct
ls -la ~/.docker/cli-plugins/docker-buildx
# Should point to: /Applications/OrbStack.app/Contents/MacOS/xbin/docker-buildx

# 3. Verify Docker can find it
docker buildx version

# 4. If still failing, ensure pipeline sets DOCKER_CONFIG:
export DOCKER_CONFIG=/Users/$(whoami)/.docker
export HOME=/Users/$(whoami)
docker buildx version
```

**Issue:** `unknown flag: --platform`

```bash
# Solution: Using Docker binary without buildx support

# 1. Check which docker is being used
which docker
# Should be: /Users/tvl/.orbstack/bin/docker

# 2. Use explicit path in pipeline
DOCKER=/Users/tvl/.orbstack/bin/docker
$DOCKER buildx version  # Should work

# 3. Avoid using system `docker` from /usr/local/bin
```

**Issue:** Buildx builder not found

```bash
# Create builder
docker buildx create --name mybuilder --use

# Bootstrap builder
docker buildx inspect --bootstrap

# List builders
docker buildx ls
```

### Pipeline Agent Issues

**Issue:** Agent offline or not picking up jobs

```bash
# Check agent status
cd ~/azure-pipelines-agent
./svc.sh status

# Restart agent
./svc.sh stop
./svc.sh start

# Check agent logs
tail -f ~/azure-pipelines-agent/agent.log

# Check diagnostic logs
ls -lt ~/azure-pipelines-agent/_diag/
```

**Issue:** PATH not set correctly in pipeline tasks

```bash
# DON'T rely on .path file for task execution
# It's only used for agent capability scanning

# DO use explicit paths in pipeline YAML:
- script: |
    DOCKER=/Users/tvl/.orbstack/bin/docker
    export DOCKER_CONFIG=/Users/tvl/.docker
    export HOME=/Users/tvl
    $DOCKER buildx version
```

### ACR Authentication Issues

**Issue:** "unauthorized: authentication required"

```bash
# Solution: Docker login not persisted to buildx builder

# 1. Login to ACR
az acr login --name acrfinriskdev

# 2. Verify credentials stored
cat ~/.docker/config.json | grep acrfinriskdev

# 3. Rebuild buildx builder if needed
docker buildx rm mybuilder
docker buildx create --name mybuilder --use
docker buildx inspect --bootstrap

# 4. Test push
docker buildx build \
  --platform linux/amd64 \
  -t acrfinriskdev.azurecr.io/test:latest \
  --push \
  .
```

### Container App Deployment Issues

**Issue:** Smoke tests fail

```bash
# Check Container App logs
az containerapp logs show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --follow

# Check app status
az containerapp show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query '{name:name,state:properties.provisioningState,status:properties.runningStatus}'

# Check revision
az containerapp revision list \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query '[0].{name:name,active:properties.active,traffic:properties.trafficWeight}'

# Test endpoints manually
APP_URL=$(az containerapp show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query properties.configuration.ingress.fqdn \
  --output tsv)

curl https://$APP_URL/health
curl https://$APP_URL/ready
curl -X POST https://$APP_URL/api/v1/validate \
  -H "Content-Type: application/json" \
  -d '{"firstName":"Test","lastName":"User","idNumber":"9001011234088"}'
```

---

## 📊 Monitoring & Metrics

### Pipeline Analytics

```bash
# In Azure DevOps:
# Pipelines > FinRisk-Application > Analytics

# Key Metrics:
# - Pass rate: Target > 95%
# - Build duration: ~2-3 minutes (with buildx)
# - Deploy duration: ~1 minute
# - Smoke test duration: ~30 seconds
```

### Application Metrics

```bash
# Container App metrics
az monitor metrics list \
  --resource $(az containerapp show \
    --name ca-finrisk-dev \
    --resource-group rg-finrisk-dev \
    --query id -o tsv) \
  --metric Requests \
  --start-time 2026-02-16T00:00:00Z

# Application Insights
# Azure Portal > appi-finrisk-dev > Logs
# Query: requests | where timestamp > ago(1h)
```

---

## 🔄 CI/CD Workflow

### Development Workflow

```bash
# 1. Make code changes
cd app/src
# Edit files...

# 2. Test locally
cd ../
uv run pytest
uv run ruff check src/

# 3. Commit and push
git add .
git commit -m "feat: add new validation rule"
git push origin main

# 4. Pipeline automatically:
#    - Runs tests (2 min)
#    - Builds AMD64 image with buildx (1 min)
#    - Pushes to ACR
#    - Deploys to Container App (1 min)
#    - Runs smoke tests including /api/v1/validate (30 sec)
#    Total: ~4-5 minutes
```

### Rollback Procedure

```bash
# Option 1: Rerun previous successful build
# Azure DevOps > Pipelines > Select previous run > Rerun

# Option 2: Manual rollback via Azure CLI
PREVIOUS_TAG="42"  # Build number of last good deployment
az containerapp update \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --image acrfinriskdev.azurecr.io/applicant-validator:$PREVIOUS_TAG
```

---

## 📚 Key Learnings & Best Practices

### Docker Buildx on Local Agents

1. ✅ **Use explicit paths**: Don't rely on PATH for Docker binary
2. ✅ **Set DOCKER_CONFIG and HOME**: Required for plugin discovery
3. ✅ **Create dedicated builder**: `docker buildx create --name mybuilder --use`
4. ✅ **Bootstrap before use**: `docker buildx inspect --bootstrap`
5. ✅ **Test locally first**: Verify buildx works before pipeline

### Pipeline Design

1. ✅ **Comprehensive smoke tests**: Test business logic, not just health checks
2. ✅ **Fast feedback**: Keep builds under 5 minutes
3. ✅ **Explicit configuration**: Don't rely on agent defaults
4. ✅ **Proper error handling**: Use `set -e` and validate each step
5. ✅ **Debug output**: Log environment state for troubleshooting

### Cross-Platform Builds

1. ✅ **Always specify platform**: `--platform linux/amd64`
2. ✅ **Use production target**: `--target production`
3. ✅ **Push directly**: `--push` (don't use `--load` for cross-platform)
4. ✅ **Verify architecture**: Check `docker inspect` shows correct arch

---

## 📚 Additional Resources

- [Azure Pipelines Documentation](https://docs.microsoft.com/en-us/azure/devops/pipelines/)
- [Docker Buildx Documentation](https://docs.docker.com/buildx/working-with-buildx/)
- [OrbStack Documentation](https://orbstack.dev/docs)
- [Azure Container Apps Deployment](https://docs.microsoft.com/en-us/azure/container-apps/)

---

**Last Updated:** 2026-02-16
**Pipeline Architecture:** Separated (Infrastructure + Application)
**Agent Type:** Self-hosted macOS (Apple Silicon) with Docker Buildx
**Deployment Target:** Azure Container Apps (AMD64)
**Build Strategy:** Cross-platform with Docker buildx

### Pipeline Files

| File | Purpose |
|------|---------|
| `azure-pipelines-infra.yml` | Terraform infrastructure provisioning |
| `azure-pipelines-app.yml` | Application build, test, deploy, verify with buildx |
