# Azure DevOps Terraform Configuration

This module configures Azure DevOps to connect with GitHub and deploy the FinRisk Platform.

## What It Creates

- **GitHub Service Connection** - Authenticates Azure DevOps with GitHub
- **Azure RM Service Connection** - Authenticates Azure DevOps with Azure
- **ACR Service Connection** - For container registry deployments
- **Variable Groups** - Infrastructure configs and secrets
- **Build Pipeline** - CI/CD pipeline from GitHub

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
# Via Azure DevOps CLI
az devops project show --project finrisk --query id -o tsv
```

### 4. Create Service Principal for Azure

```bash
az ad sp create-for-rbac \
  --name "azure-devops-finrisk" \
  --role Contributor \
  --scopes /subscriptions/$(az account show --query id -o tsv) \
  --sdk-auth
```

## Usage

### 1. Create terraform.tfvars

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

| Variable | Description | Required |
|----------|-------------|----------|
| `azuredevops_org_service_url` | Azure DevOps org URL (https://dev.azure.com/your-org) | Yes |
| `azuredevops_pat` | Azure DevOps PAT | Yes |
| `project_id` | Azure DevOps project ID | Yes |
| `repository` | GitHub repo (owner/repo) | Yes |
| `subscription_id` | Azure subscription ID | Yes |
| `azure_client_id` | Azure SP client ID | Yes |
| `azure_client_secret` | Azure SP client secret | Yes |
| `azure_tenant_id` | Azure tenant ID | Yes |

## After Apply

1. Go to Azure DevOps → Pipelines
2. Find the `finrisk-ci-cd` pipeline
3. Run the pipeline to deploy

## Manual Alternative

If you prefer manual setup:

1. **Azure DevOps** → Project Settings → Service connections
2. **New connection** → GitHub → Authorize
3. **New connection** → Azure Resource Manager → Service Principal
4. **Pipelines** → New Pipeline → GitHub → Select repo → Existing YAML
