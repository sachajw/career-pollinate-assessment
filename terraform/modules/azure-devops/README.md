# Azure DevOps Terraform Module

This module configures Azure DevOps to connect with GitHub and deploy the FinRisk Platform.

## What It Creates

| Resource | Description |
|----------|-------------|
| GitHub Service Connection | OAuth connection to GitHub repository |
| Azure RM Service Connection | Service Principal auth for Azure deployments |
| ACR Service Connection | Container Registry authentication |
| Variable Group (Infrastructure) | Non-secret config variables |
| Variable Group (Secrets) | Secret credentials including RISKSHIELD_API_KEY |
| Build Pipeline | CI/CD pipeline from GitHub YAML |

## Prerequisites

### 1. Create Azure DevOps Organization & Project

```bash
# Via browser: https://dev.azure.com
# Create organization: your-org
# Create project: finrisk
```

### 2. Get Azure DevOps PAT

1. Go to https://dev.azure.com → User Settings → Personal Access Tokens
2. Create new token with scopes:
   - **Build (Read & Execute)**
   - **Code (Read)**
   - **Project (Read, Write)**
   - **Release (Read, Write)**
   - **Service Connections (Read, Write)**

### 3. Get Your Project ID

```bash
az devops project show --project finrisk --query id -o tsv
```

### 4. Create Service Principal for Azure

```bash
az ad sp create-for-rbac \
  --name "azure-devops-finrisk" \
  --role Contributor \
  --scopes /subscriptions/$(az account show --query id -o tsv)
```

## Usage

### 1. Navigate to devops directory

```bash
cd terraform/devops
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### 2. Initialize and Apply

```bash
terraform init
terraform plan
terraform apply
```

## Variables

### Required

| Variable | Description |
|----------|-------------|
| `project_id` | Azure DevOps project ID |
| `repository` | GitHub repository (owner/repo) |
| `subscription_id` | Azure subscription ID |
| `subscription_name` | Azure subscription name |
| `resource_group_name` | Azure resource group name |
| `location` | Azure region |
| `container_registry_name` | ACR name |
| `container_app_name` | Container App name |
| `key_vault_name` | Key Vault name |
| `azure_client_id` | Azure SP client ID |
| `azure_client_secret` | Azure SP client secret |
| `azure_tenant_id` | Azure tenant ID |

### Optional (with defaults)

| Variable | Default | Description |
|----------|---------|-------------|
| `project_name` | `finrisk` | Project name prefix |
| `environment` | `dev` | Environment name |
| `service_connection_name` | `finrisk` | Service connection prefix |
| `branch` | `main` | Default branch |
| `pipeline_yaml_path` | `/pipelines/azure-pipelines.yml` | Path to pipeline YAML |
| `riskshield_api_key` | `""` | RiskShield API key (secret) |

## Outputs

| Output | Description |
|--------|-------------|
| `pipeline_id` | ID of the created build pipeline |
| `github_service_connection_id` | GitHub service connection ID |
| `azure_rm_service_connection_id` | Azure RM service connection ID |

## After Apply

1. Go to Azure DevOps → Pipelines
2. Find the `finrisk-ci-cd` pipeline
3. Authorize the GitHub connection if prompted
4. Run the pipeline to deploy

## Manual Alternative

If you prefer manual setup:

1. **Azure DevOps** → Project Settings → Service connections
2. **New connection** → GitHub → Authorize
3. **New connection** → Azure Resource Manager → Service Principal
4. **Pipelines** → New Pipeline → GitHub → Select repo → Existing YAML
