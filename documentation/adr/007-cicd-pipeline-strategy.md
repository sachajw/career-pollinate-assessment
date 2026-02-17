# ADR-007: CI/CD Pipeline Strategy (Azure DevOps)

**Status:** Accepted
**Date:** 2026-02-14
**Decision Makers:** Platform Engineering Team
**Technical Story:** RiskShield API Integration Platform

## Context

The RiskShield integration platform requires a robust CI/CD pipeline that:
- Automates testing, building, and deployment
- Manages separate environments (dev, prod)
- Handles secrets securely
- Provides manual approvals for production
- Includes infrastructure deployment (Terraform)
- Supports rollback on failure

The technical assessment requires:
- Stage 1: Build (tests, Docker build, scan, push to ACR)
- Stage 2: Infrastructure (Terraform init/plan/apply)
- Stage 3: Deploy (deploy container, smoke test)
- Service connections for Azure authentication
- Variable groups for configuration
- Secure secret handling
- Separate environments (dev/prod)

## Decision

We will use **Azure DevOps YAML Pipelines** with a **3-stage structure** (Build → Infrastructure → Deploy) with **environment-based approvals**.

## Pipeline Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                        Azure DevOps Pipeline                          │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌─────────────┐     ┌─────────────────┐     ┌─────────────────┐     │
│  │   BUILD     │────▶│  INFRASTRUCTURE │────▶│     DEPLOY      │     │
│  │   Stage     │     │     Stage       │     │     Stage       │     │
│  └─────────────┘     └─────────────────┘     └─────────────────┘     │
│        │                    │                      │                  │
│        ▼                    ▼                      ▼                  │
│  • Lint (Ruff)        • Terraform init      • Update Container App   │
│  • Type check (mypy)  • Terraform plan      • Wait for rollout       │
│  • Unit tests         • Terraform apply     • Smoke test /health     │
│  • Docker build       • (manual approval    • Verify response        │
│  • Trivy scan           for prod)                                      │
│  • Push to ACR                                                       │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘
```

## Pipeline Structure

### Full Pipeline Definition

```yaml
# pipelines/azure-pipelines.yml
trigger:
  branches:
    include:
      - main
  paths:
    exclude:
      - documentation/**
      - '*.md'

pr:
  branches:
    include:
      - main

variables:
  - template: variables/global.yml
  - group: finrisk-common

stages:
  # ============================================================================
  # STAGE 1: BUILD
  # ============================================================================
  - stage: Build
    displayName: 'Build & Test'
    jobs:
      - job: Build
        displayName: 'Build and Test Application'
        pool:
          vmImage: 'ubuntu-latest'

        steps:
          # 1. Setup Python
          - task: UsePythonVersion@0
            inputs:
              versionSpec: '3.13'
              addToPath: true

          # 2. Install uv
          - script: |
              curl -LsSf https://astral.sh/uv/install.sh | sh
              echo "$HOME/.local/bin" >> $GITHUB_PATH
            displayName: 'Install uv package manager'

          # 3. Install dependencies
          - script: |
              cd app
              uv sync --frozen
            displayName: 'Install dependencies'

          # 4. Lint (Ruff)
          - script: |
              cd app
              uv run ruff check src/
            displayName: 'Lint with Ruff'
            continueOnError: false

          # 5. Type check (mypy)
          - script: |
              cd app
              uv run mypy src/ --strict
            displayName: 'Type check with mypy'
            continueOnError: false

          # 6. Run tests
          - script: |
              cd app
              uv run pytest tests/ -v --junitxml=test-results.xml --cov=src --cov-report=xml
            displayName: 'Run unit tests'

          - task: PublishTestResults@2
            inputs:
              testResultsFiles: 'app/test-results.xml'
              testRunTitle: 'Unit Tests'

          - task: PublishCodeCoverageResults@2
            inputs:
              summaryFileLocation: 'app/coverage.xml'

          # 7. Build Docker image
          - task: Docker@2
            displayName: 'Build Docker image'
            inputs:
              command: build
              dockerfile: app/Dockerfile
              buildContext: app
              tags: |
                $(Build.BuildId)
                latest

          # 8. Scan image for vulnerabilities (Trivy)
          - script: |
              docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                aquasec/trivy:latest image --severity HIGH,CRITICAL --exit-code 1 \
                applicant-validator:$(Build.BuildId)
            displayName: 'Scan image with Trivy'

          # 9. Push to ACR
          - task: Docker@2
            displayName: 'Push to Azure Container Registry'
            inputs:
              command: push
              containerRegistry: $(acrServiceConnection)
              repository: applicant-validator
              tags: |
                $(Build.BuildId)
                latest

  # ============================================================================
  # STAGE 2: INFRASTRUCTURE (DEV)
  # ============================================================================
  - stage: Infrastructure_Dev
    displayName: 'Infrastructure (Dev)'
    dependsOn: Build
    condition: succeeded()
    variables:
      - template: variables/dev.yml
      - group: finrisk-dev-secrets
    jobs:
      - deployment: Terraform
        displayName: 'Deploy Infrastructure to Dev'
        environment: 'dev'
        pool:
          vmImage: 'ubuntu-latest'
        strategy:
          runOnce:
            deploy:
              steps:
                - task: TerraformInstaller@1
                  inputs:
                    terraformVersion: '1.5.7'

                - task: TerraformTaskV4@4
                  displayName: 'Terraform Init'
                  inputs:
                    provider: 'azurerm'
                    command: 'init'
                    commandOptions: '-backend-config=backend.hcl'
                    backendServiceArm: $(azureServiceConnection)
                    backendAzureRmResourceGroupName: 'rg-terraform-state'
                    backendAzureRmStorageAccountName: 'sttfstatefinrisk001'
                    backendAzureRmContainerName: 'tfstate'
                    backendAzureRmKey: 'finrisk-dev.tfstate'

                - task: TerraformTaskV4@4
                  displayName: 'Terraform Plan'
                  inputs:
                    provider: 'azurerm'
                    command: 'plan'
                    commandOptions: '-out=tfplan -var="riskshield_api_key=$(RISKSHIELD_API_KEY)"'
                    environmentServiceNameAzureRM: $(azureServiceConnection)

                - task: TerraformTaskV4@4
                  displayName: 'Terraform Apply'
                  inputs:
                    provider: 'azurerm'
                    command: 'apply'
                    commandOptions: 'tfplan'
                    environmentServiceNameAzureRM: $(azureServiceConnection)

  # ============================================================================
  # STAGE 3: DEPLOY (DEV)
  # ============================================================================
  - stage: Deploy_Dev
    displayName: 'Deploy Application (Dev)'
    dependsOn: Infrastructure_Dev
    condition: succeeded()
    variables:
      - template: variables/dev.yml
    jobs:
      - deployment: Deploy
        displayName: 'Deploy to Dev'
        environment: 'dev'
        pool:
          vmImage: 'ubuntu-latest'
        strategy:
          runOnce:
            deploy:
              steps:
                - task: AzureContainerApps@1
                  displayName: 'Update Container App'
                  inputs:
                    azureSubscription: $(azureServiceConnection)
                    containerAppName: 'ca-finrisk-dev'
                    resourceGroup: 'rg-finrisk-dev'
                    imageToDeploy: 'acrfinriskdev001.azurecr.io/applicant-validator:$(Build.BuildId)'

                - script: |
                    echo "Waiting for rollout..."
                    sleep 30
                  displayName: 'Wait for rollout'

                - script: |
                    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" https://ca-finrisk-dev.eastus2.azurecontainerapps.io/health)
                    if [ "$RESPONSE" != "200" ]; then
                      echo "Smoke test failed: /health returned $RESPONSE"
                      exit 1
                    fi
                    echo "Smoke test passed"
                  displayName: 'Smoke test - Health check'

  # ============================================================================
  # STAGE 2 & 3: INFRASTRUCTURE + DEPLOY (PROD)
  # ============================================================================
  - stage: Deploy_Prod
    displayName: 'Deploy to Production'
    dependsOn: Deploy_Dev
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
    variables:
      - template: variables/prod.yml
      - group: finrisk-prod-secrets
    jobs:
      - deployment: Deploy
        displayName: 'Deploy to Production'
        environment: 'prod'  # Requires manual approval
        pool:
          vmImage: 'ubuntu-latest'
        strategy:
          runOnce:
            deploy:
              steps:
                - task: TerraformInstaller@1
                  inputs:
                    terraformVersion: '1.5.7'

                - task: TerraformTaskV4@4
                  displayName: 'Terraform Init (Prod)'
                  inputs:
                    provider: 'azurerm'
                    command: 'init'
                    commandOptions: '-backend-config=backend.hcl'
                    backendServiceArm: $(azureServiceConnection)
                    backendAzureRmResourceGroupName: 'rg-terraform-state'
                    backendAzureRmStorageAccountName: 'sttfstatefinrisk001'
                    backendAzureRmContainerName: 'tfstate'
                    backendAzureRmKey: 'finrisk-prod.tfstate'

                - task: TerraformTaskV4@4
                  displayName: 'Terraform Plan (Prod)'
                  inputs:
                    provider: 'azurerm'
                    command: 'plan'
                    commandOptions: '-out=tfplan -var="riskshield_api_key=$(RISKSHIELD_API_KEY)"'
                    environmentServiceNameAzureRM: $(azureServiceConnection)

                - task: TerraformTaskV4@4
                  displayName: 'Terraform Apply (Prod)'
                  inputs:
                    provider: 'azurerm'
                    command: 'apply'
                    commandOptions: 'tfplan'
                    environmentServiceNameAzureRM: $(azureServiceConnection)

                - task: AzureContainerApps@1
                  displayName: 'Update Container App (Prod)'
                  inputs:
                    azureSubscription: $(azureServiceConnection)
                    containerAppName: 'ca-finrisk-prod'
                    resourceGroup: 'rg-finrisk-prod'
                    imageToDeploy: 'acrfinriskprod001.azurecr.io/applicant-validator:$(Build.BuildId)'

                - script: |
                    echo "Waiting for production rollout..."
                    sleep 60
                  displayName: 'Wait for production rollout'

                - script: |
                    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" https://ca-finrisk-prod.eastus2.azurecontainerapps.io/health)
                    if [ "$RESPONSE" != "200" ]; then
                      echo "Production smoke test failed"
                      exit 1
                    fi
                    echo "Production smoke test passed"
                  displayName: 'Smoke test - Production health check'
```

## Decision 1: 3-Stage Pipeline Structure

### Rationale

| Stage          | Purpose                          | Automated | Approval    |
| -------------- | -------------------------------- | --------- | ----------- |
| **Build**      | Quality gates + artifact creation | ✅ Yes    | None        |
| **Infrastructure** | Provision/updates Azure resources | ✅ Yes    | Prod only   |
| **Deploy**     | Release to environment           | ✅ Yes    | Prod only   |

### Stage Dependencies

```
Build → Infrastructure_Dev → Deploy_Dev → Deploy_Prod
                                          ↑
                                    (Manual Approval)
```

## Decision 2: Service Connections

### Azure Resource Manager Service Connection

```yaml
# Service Connection: azure-finrisk-service-connection
# Type: Azure Resource Manager (Service Principal)
# Scope: Subscription
# Permissions: Contributor on target resource groups
```

### ACR Service Connection

```yaml
# Service Connection: acr-finrisk-connection
# Type: Container Registry
# Registry: acrfinriskdev001.azurecr.io
# Authentication: Managed Identity
```

## Decision 3: Variable Groups

### Structure

```
┌─────────────────────────────────────────────────────────────┐
│                    Variable Groups                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  finrisk-common (shared)                                    │
│  ├── azureServiceConnection: azure-finrisk-sc               │
│  ├── acrServiceConnection: acr-finrisk-sc                   │
│  └── pythonVersion: 3.13                                    │
│                                                              │
│  finrisk-dev-secrets (dev-specific)                         │
│  ├── RISKSHIELD_API_KEY: *** (secret)                       │
│  └── ENVIRONMENT: dev                                       │
│                                                              │
│  finrisk-prod-secrets (prod-specific)                       │
│  ├── RISKSHIELD_API_KEY: *** (secret)                       │
│  └── ENVIRONMENT: prod                                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Variable Templates

```yaml
# pipelines/variables/global.yml
variables:
  azureServiceConnection: 'azure-finrisk-service-connection'
  acrServiceConnection: 'acr-finrisk-connection'
  pythonVersion: '3.13'
  terraformVersion: '1.5.7'

# pipelines/variables/dev.yml
variables:
  environment: 'dev'
  resourceGroupName: 'rg-finrisk-dev'
  containerAppName: 'ca-finrisk-dev'
  acrName: 'acrfinriskdev001'
  location: 'eastus2'

# pipelines/variables/prod.yml
variables:
  environment: 'prod'
  resourceGroupName: 'rg-finrisk-prod'
  containerAppName: 'ca-finrisk-prod'
  acrName: 'acrfinriskprod001'
  location: 'eastus2'
```

## Decision 4: Environment-Based Approvals

### Dev Environment

- **Approval**: None (automatic after Build succeeds)
- **Rationale**: Fast iteration, developers need quick feedback

### Production Environment

- **Approval**: Required (manual)
- **Approvers**: Platform Engineering Lead, Security Architect
- **Timeout**: 7 days (then auto-reject)
- **Rationale**: Prevent accidental production deployments

### Azure DevOps Environment Configuration

```yaml
# Environments in Azure DevOps:
# - dev: No approval required
# - prod: Requires approval from "Platform Leads" group
```

## Decision 5: Secure Secret Handling

### Secrets Flow

```
┌──────────────────┐     ┌───────────────────┐     ┌──────────────────┐
│  Azure DevOps    │     │  Pipeline         │     │   Key Vault      │
│  Variable Group  │────▶│  Variable         │────▶│   Secret         │
│  (encrypted)     │     │  (masked in logs) │     │   (stored)       │
└──────────────────┘     └───────────────────┘     └──────────────────┘
```

### Best Practices

1. **Never log secrets**: Azure DevOps masks secret variables automatically
2. **Rotate secrets**: API keys rotated every 90 days
3. **Limit access**: Variable groups have RBAC
4. **Audit trail**: All secret access is logged

### Terraform Secret Injection

```hcl
# Secret passed via -var flag (not in state file)
terraform apply -var="riskshield_api_key=$RISKSHIELD_API_KEY"

# Marked as sensitive in variables.tf
variable "riskshield_api_key" {
  type      = string
  sensitive = true  # Not shown in plan output
}
```

## Decision 6: Rollback Strategy

### Automatic Rollback

```yaml
# Rollback on smoke test failure
- script: |
    # Attempt rollback to previous image
    PREVIOUS_IMAGE=$(az containerapp show \
      --name ca-finrisk-prod \
      --resource-group rg-finrisk-prod \
      --query properties.template.containers[0].image \
      --output tsv)

    echo "Rolling back to: $PREVIOUS_IMAGE"

    az containerapp update \
      --name ca-finrisk-prod \
      --resource-group rg-finrisk-prod \
      --container-image $PREVIOUS_IMAGE
  condition: failed()
  displayName: 'Rollback on failure'
```

### Manual Rollback

```bash
# Quick rollback via Azure CLI
az containerapp revision deactivate \
  --name ca-finrisk-prod \
  --resource-group rg-finrisk-prod \
  --revision <previous-revision-name>

# Or set traffic to previous revision
az containerapp ingress traffic set \
  --name ca-finrisk-prod \
  --resource-group rg-finrisk-prod \
  --revision-weight <previous-revision>=100
```

## Quality Gates

### Build Stage Gates

| Gate            | Tool     | Failure Action |
| --------------- | -------- | -------------- |
| Linting         | Ruff     | Fail pipeline  |
| Type Checking   | mypy     | Fail pipeline  |
| Unit Tests      | pytest   | Fail pipeline  |
| Code Coverage   | pytest-cov | Warn <80%    |
| Image Scan      | Trivy    | Fail on HIGH/CRITICAL |

### Infrastructure Stage Gates

| Gate            | Tool      | Failure Action |
| --------------- | --------- | -------------- |
| Terraform Validate | terraform | Fail pipeline  |
| Terraform Plan  | terraform | Fail pipeline  |
| Drift Detection | terraform plan | Alert on changes |

### Deploy Stage Gates

| Gate            | Tool    | Failure Action |
| --------------- | ------- | -------------- |
| Health Check    | curl    | Fail + Rollback |
| Response Time   | curl    | Alert if >5s   |
| Error Rate      | App Insights | Alert if >1% |

## Branch Strategy Integration

### Main Branch Protection

```
main (protected)
├── Requires PR
├── Requires Build stage to pass
├── Requires 1 reviewer
└── Auto-deploys to dev after merge
```

### Feature Branches

```yaml
# PR builds run Build stage only
pr:
  branches:
    include:
      - main
# PR does NOT trigger Infrastructure or Deploy stages
```

## Consequences

### Positive

- ✅ **Automation**: Fully automated from commit to deployment
- ✅ **Security**: Secrets handled securely, never in logs
- ✅ **Quality**: Multiple gates prevent bad deployments
- ✅ **Approval**: Production requires manual sign-off
- ✅ **Rollback**: Can revert to previous version quickly
- ✅ **Traceability**: Full audit trail of changes

### Negative

- ⚠️ **Complexity**: Multi-stage pipeline is complex
- ⚠️ **Approval Delay**: Production deployments wait for approval
- ⚠️ **Maintenance**: Pipeline code needs updates

### Mitigations

- Comprehensive pipeline documentation
- Pipeline templates for reusability
- Regular pipeline reviews

## Compliance with Technical Assessment

| Requirement              | Status | Implementation                        |
| ------------------------ | ------ | ------------------------------------- |
| Stage 1: Build           | ✅     | Lint, test, build, scan, push         |
| Stage 2: Infrastructure  | ✅     | Terraform init/plan/apply             |
| Stage 3: Deploy          | ✅     | Container update, smoke test          |
| Service connections      | ✅     | Azure RM + ACR connections            |
| Variable groups          | ✅     | Shared + environment-specific         |
| Secure secret handling   | ✅     | Secret variables, masked logs         |
| Separate environments    | ✅     | Dev (auto) + Prod (manual approval)   |

## Related Decisions

- [ADR-005: Docker Container Strategy](./005-docker-container-strategy.md)
- [ADR-006: Terraform Module Architecture](./006-terraform-module-architecture.md)
- [ADR-003: Managed Identity for Security](./003-managed-identity-security.md)

## References

- [Azure DevOps YAML Pipelines](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/)
- [Azure Container Apps Deployment](https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/deploy/azure-container-apps)
- [Terraform Azure DevOps Task](https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/terraform/terraform-task-v4)

## Review & Approval

| Role                      | Name   | Date       | Status      |
| ------------------------- | ------ | ---------- | ----------- |
| Solution Architect        | [Name] | 2026-02-14 | ✅ Approved |
| Platform Engineering Lead | [Name] | 2026-02-14 | ✅ Approved |
| DevOps Lead               | [Name] | 2026-02-14 | ✅ Approved |
| Security Architect        | [Name] | 2026-02-14 | ✅ Approved |

---

**Last Updated:** 2026-02-14
**Next Review:** 2026-08-14 (6 months)
