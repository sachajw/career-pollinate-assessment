# Azure DevOps CI/CD Pipelines

This directory contains the CI/CD pipeline configuration for automated deployment of the RiskShield API Integration Platform.

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

## Infrastructure Pipeline (`azure-pipelines-infra.yml`)

**Purpose:** Provision and manage Azure infrastructure with Terraform

### Stage 1: Plan

**Steps:**
- Initialize Terraform with remote state
- Validate configuration
- Generate execution plan
- Publish plan as artifact

### Stage 2: Apply

**Steps:**
- Download plan artifact
- Apply infrastructure changes
- Save Terraform outputs

**Trigger:** Changes to `terraform/**` directory

**Approval:** Required for main branch (environment: `dev-infrastructure`)

---

## Application Pipeline (`azure-pipelines-app.yml`)

**Purpose:** Build, test, and deploy the containerized application

### Stage 1: Build & Test

**Jobs:**

1. **Test Job**
   - Setup Python 3.13
   - Install dependencies with uv
   - Lint with Ruff
   - Type check with mypy
   - Security scan with Bandit
   - Run unit tests with pytest
   - Publish test results and code coverage

2. **Build Image Job**
   - Build Docker image (`--target production`)
   - Scan image with Trivy
   - Push to Azure Container Registry

**Quality Gates:**
- ✅ All tests must pass
- ✅ Code coverage > 80%
- ⚠️ No critical security vulnerabilities

### Stage 2: Deploy

**Steps:**
- Update Container App with new image
- Wait for deployment to stabilize

**Deployment Strategy:** Rolling update (zero-downtime)

### Stage 3: Verify

**Steps:**
- Health check (`/health`)
- Readiness check (`/ready`)
- OpenAPI docs check (`/docs`)

**Rollback:** Manual rollback via Azure Portal if smoke tests fail

**Trigger:** Changes to `app/**` directory

---

## Pipeline Execution Order

1. **First-time setup:** Run infrastructure pipeline to create resources
2. **Subsequent deployments:** Application pipeline deploys new container images
3. **Infrastructure changes:** Run infrastructure pipeline when modifying Terraform

## 🚀 Setup Instructions

### Prerequisites

1. **Azure DevOps Project**
   - Create a new project or use existing
   - Enable pipelines feature

2. **Azure Subscription**
   - Active Azure subscription
   - Contributor access to create resources

3. **Service Connections**
   - Azure Resource Manager service connection
   - Azure Container Registry service connection

### Step 1: Create Service Connections

#### Azure Resource Manager Service Connection

```bash
# In Azure DevOps:
# Project Settings > Service connections > New service connection > Azure Resource Manager

# Select authentication method:
# - Service Principal (automatic) - Recommended
# - Managed Identity (for self-hosted agents)

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
# - Azure Container Registry: Select your ACR (created by Terraform)
# - Service connection name: acr-service-connection
# - Grant access to all pipelines: Yes
```

### Step 2: Create Variable Group

```bash
# In Azure DevOps:
# Pipelines > Library > + Variable group

# Variable group name: finrisk-dev

# Required Variables:
# - terraformStateStorageAccount: stterraformstate<unique> (created manually for TF state)

# After running Terraform, add these outputs:
# - containerRegistry: acrfinriskdev.azurecr.io (from TF output: container_registry_login_server)

# Link secrets from Azure Key Vault (optional but recommended):
# - Enable "Link secrets from an Azure key vault"
# - Select Azure subscription
# - Select Key Vault: kv-finrisk-dev
# - Authorize
# - Add: RISKSHIELD-API-KEY
```

### Step 3: Create Infrastructure Pipeline

```bash
# In Azure DevOps:
# Pipelines > New pipeline > Azure Repos Git > Select your repository

# Configure:
# - Pipeline name: FinRisk-Infrastructure
# - YAML file path: /pipelines/azure-pipelines-infra.yml
# - Save (don't run yet - need to set up backend storage first)
```

### Step 4: Create Application Pipeline

```bash
# In Azure DevOps:
# Pipelines > New pipeline > Azure Repos Git > Select your repository

# Configure:
# - Pipeline name: FinRisk-Application
# - YAML file path: /pipelines/azure-pipelines-app.yml
# - Save (run after infrastructure exists)
```

### Step 5: Configure Environments

```bash
# In Azure DevOps:
# Pipelines > Environments > New environment

# Create two environments:
# 1. Environment name: dev
#    Description: Development environment (for app deployments)
#    Add approvers: Optional for dev

# 2. Environment name: dev-infrastructure
#    Description: Infrastructure changes (for Terraform)
#    Add approvers: Recommended for production safety
```

### Step 6: Initial Deployment Order

1. **Run Infrastructure Pipeline First**
   ```bash
   # Manually trigger the infrastructure pipeline
   # This creates:
   # - Resource Group
   # - Container Registry
   # - Container App Environment
   # - Container App
   # - Key Vault
   # - Log Analytics + Application Insights
   ```

2. **Run Application Pipeline**
   ```bash
   # After infrastructure exists, trigger the app pipeline
   # This will:
   # - Build and test the application
   # - Push container image to ACR
   # - Deploy to Container App
   # - Run smoke tests
   ```

## 📝 Pipeline Configuration

### Variables

#### Infrastructure Pipeline (`azure-pipelines-infra.yml`)

```yaml
variables:
  - group: finrisk-dev
  - name: azureSubscription
    value: "azure-service-connection"
  - name: environmentName
    value: "dev"
  - name: terraformVersion
    value: "1.7.0"
  - name: terraformWorkingDirectory
    value: "$(System.DefaultWorkingDirectory)/terraform/environments/dev"
```

#### Application Pipeline (`azure-pipelines-app.yml`)

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
    value: "acrfinriskdev.azurecr.io"      # Matches Terraform: acr${project_name}${environment}
  - name: imageName
    value: "applicant-validator"            # Domain service name (DDD)
  - name: containerAppName
    value: "ca-finrisk-dev"                 # Matches Terraform: ca-${project_name}-${environment}
  - name: resourceGroupName
    value: "rg-finrisk-dev"                 # Matches Terraform: rg-${project_name}-${environment}
```

> **Note:** Variable names must match the Terraform naming convention. If you change `project_name` in Terraform, update these pipeline variables accordingly.

### Naming Convention Mapping (DDD-Aligned)

Resources created by Terraform follow this pattern:

| Resource | Terraform Format | Dev Environment Value |
|----------|------------------|----------------------|
| Resource Group | `rg-{project}-{env}` | `rg-finrisk-dev` |
| Container App | `ca-{project}-{env}` | `ca-finrisk-dev` |
| Container App Env | `cae-{project}-{env}` | `cae-finrisk-dev` |
| Container Registry | `acr{project}{env}` | `acrfinriskdev` |
| Key Vault | `kv-{project}-{env}` | `kv-finrisk-dev` |
| Log Analytics | `log-{project}-{env}` | `log-finrisk-dev` |
| App Insights | `appi-{project}-{env}` | `appi-finrisk-dev` |
| Container/Image | Domain service name | `applicant-validator` |

**DDD Naming Rationale:**
- `finrisk` = **FinSure** + **Risk** validation context
- `applicant-validator` = Domain service that validates loan applicants

Set in `terraform/environments/dev/variables.tf`:
- `project_name` = `"finrisk"`
- `environment` = `"dev"`

### Triggers

#### Infrastructure Pipeline Triggers

```yaml
trigger:
  branches:
    include:
      - main
  paths:
    include:
      - terraform/**
      - pipelines/azure-pipelines-infra.yml

pr:
  branches:
    include:
      - main
  paths:
    include:
      - terraform/**
```

#### Application Pipeline Triggers

```yaml
trigger:
  branches:
    include:
      - main
      - develop
  paths:
    include:
      - app/**
      - pipelines/azure-pipelines-app.yml

pr:
  branches:
    include:
      - main
  paths:
    include:
      - app/**
```

## 🔐 Secrets Management

### Variable Group Secrets

Secrets are stored in Azure DevOps variable groups:

```bash
# Mark secrets as secret (hidden in logs)
# - Click the lock icon next to the variable
# - Value will be masked in pipeline logs
```

### Key Vault Integration

Link secrets directly from Azure Key Vault:

```bash
# In Variable Group:
# Link secrets from an Azure key vault
# Select: kv-finrisk-dev
# Add variables: RISKSHIELD-API-KEY
```

### Service Principal Credentials

Service connections handle authentication automatically:

- No need to manage credentials manually
- Tokens are short-lived and auto-rotated
- Access is scoped to specific resources

## 🛠️ Pipeline Maintenance

### Update Container Image

Application pipeline automatically builds and deploys on commit to `main` branch:

```bash
# 1. Make code changes in app/
git add .
git commit -m "feat: add new endpoint"
git push origin main

# 2. Application pipeline triggers automatically
# 3. New image built with Build.BuildId as tag
# 4. Container App updated with new image
# 5. Smoke tests verify deployment
```

### Update Infrastructure

Infrastructure pipeline triggers on changes to `terraform/` directory:

```bash
# 1. Make infrastructure changes
cd terraform/environments/dev
# Edit main.tf or terraform.tfvars

# 2. Commit and push
git add .
git commit -m "feat: add new infrastructure"
git push origin main

# 3. Infrastructure pipeline runs Terraform plan
# 4. Apply requires approval (dev-infrastructure environment)
```

### Manual Pipeline Run

```bash
# In Azure DevOps:

# For Infrastructure:
# Pipelines > FinRisk-Infrastructure > Run pipeline

# For Application:
# Pipelines > FinRisk-Application > Run pipeline

# Options:
# - Branch: Select branch to deploy
# - Variables: Override variables if needed
# - Stages to run: Select specific stages
```

### Rollback Deployment

```bash
# Option 1: Redeploy previous build
# Pipelines > FinRisk-Application > Select previous successful run > Rerun

# Option 2: Azure CLI
PREVIOUS_IMAGE="acrfinriskdev.azurecr.io/applicant-validator:<previous-build-id>"

az containerapp update \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --image $PREVIOUS_IMAGE
```

## 📊 Monitoring Pipelines

### Build Status

View build status in Azure DevOps:

- **Pipelines > Recent runs**
- Click on build to see detailed logs
- Check stage/job status and logs

### Pipeline-Specific Monitoring

```bash
# Infrastructure Pipeline Analytics
# Pipelines > FinRisk-Infrastructure > Analytics

# Application Pipeline Analytics
# Pipelines > FinRisk-Application > Analytics

# Metrics:
# - Pass rate
# - Duration trend
# - Task duration
# - Agent pool usage
```

### Build Notifications

Configure notifications:

```bash
# Project Settings > Notifications > New subscription

# Events:
# - Build completed (infrastructure)
# - Build completed (application)
# - Build failed
# - Deployment to environment failed

# Subscribers:
# - Team email
# - Slack channel (via webhook)
# - PagerDuty (for critical failures)
```

## 🧪 Testing Pipelines Locally

### Validate YAML

```bash
# Install Azure CLI
az extension add --name azure-devops

# Login to Azure DevOps
az devops login

# Validate infrastructure pipeline
az pipelines validate --yaml-path pipelines/azure-pipelines-infra.yml

# Validate application pipeline
az pipelines validate --yaml-path pipelines/azure-pipelines-app.yml
```

### Test Application Steps Locally

```bash
# 1. Test Python steps
cd app
uv sync
uv run pytest
uv run ruff check src/
uv run mypy src/

# 2. Test Docker build (production target)
docker build --target production -t applicant-validator:local .

# 3. Run container and test
docker run -p 8080:8080 -e RISKSHIELD_API_KEY=test applicant-validator:local
curl http://localhost:8080/health
```

### Test Infrastructure Steps Locally

```bash
# Test Terraform
cd terraform/environments/dev
cp backend.hcl.example backend.hcl
# Edit backend.hcl with your storage account
terraform init -backend-config=backend.hcl
terraform validate
terraform plan
```

## 🚨 Troubleshooting

### Infrastructure Pipeline Issues

**Issue:** Terraform init fails

```bash
# Check backend configuration
# Verify storage account exists and you have access
az storage account show \
  --name stterraformstate<unique> \
  --resource-group rg-terraform-state

# Check service connection has correct permissions
# Required: Storage Blob Data Contributor
```

**Issue:** Terraform plan/apply fails

```bash
# Check Terraform logs in pipeline
# Common issues:
# - Invalid variable values
# - Resource name conflicts
# - Insufficient permissions

# Test locally
cd terraform/environments/dev
terraform init -backend-config=backend.hcl
terraform plan
```

### Application Pipeline Issues

**Issue:** Tests failing

```bash
# Check test output in pipeline logs
# Run tests locally to reproduce
cd app
uv run pytest --verbose

# Fix issues and commit
git add .
git commit -m "fix: resolve test failures"
git push
```

**Issue:** Docker build fails

```bash
# Check Dockerfile syntax
# Build locally to reproduce
cd app
docker build -t applicant-validator:local .

# Common issues:
# - Missing dependencies in pyproject.toml
# - Incorrect file paths in COPY commands
# - Base image not available
```

**Issue:** Container App update fails

```bash
# Check Container App exists (run infra pipeline first!)
az containerapp show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev

# Check image exists in ACR
az acr repository show-tags \
  --name acrfinriskdev \
  --repository applicant-validator

# Check service connection has AcrPull permission
```

**Issue:** Smoke tests fail

```bash
# Check application logs
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
curl https://$APP_URL/ready
```

## 📚 Additional Resources

- [Azure Pipelines Documentation](https://docs.microsoft.com/en-us/azure/devops/pipelines/)
- [Terraform in Azure Pipelines](https://docs.microsoft.com/en-us/azure/devops/pipelines/tasks/deploy/terraform)
- [Docker in Azure Pipelines](https://docs.microsoft.com/en-us/azure/devops/pipelines/tasks/build/docker)
- [Azure Container Apps Deployment](https://docs.microsoft.com/en-us/azure/container-apps/deploy-azure-devops)

---

**Last Updated:** 2026-02-15
**Pipeline Architecture:** Separated (Infrastructure + Application)
**Maintained By:** Platform Engineering Team

### Pipeline Files

| File | Purpose |
|------|---------|
| `azure-pipelines-infra.yml` | Terraform infrastructure provisioning |
| `azure-pipelines-app.yml` | Application build, test, deploy, verify |
