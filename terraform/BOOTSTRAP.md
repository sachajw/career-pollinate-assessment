# Terraform Bootstrap - Prerequisites

## Overview

This document describes the **manual prerequisites** required before Terraform can run. These are one-time setup steps that cannot be managed by Terraform itself due to chicken-and-egg dependencies.

---

## Prerequisites Checklist

### ✅ 1. Backend Storage Account

The Terraform state backend storage account must exist before running Terraform.

**Resource Group:** `rg-terraform-state`
**Storage Account:** `stfinrisktf4d9e8d`
**Container:** `tfstate`

#### Creation (if needed):

```bash
# Create resource group
az group create \
  --name rg-terraform-state \
  --location eastus2

# Create storage account
az storage account create \
  --name stfinrisktf4d9e8d \
  --resource-group rg-terraform-state \
  --location eastus2 \
  --sku Standard_LRS \
  --encryption-services blob \
  --https-only true \
  --min-tls-version TLS1_2

# Create container
az storage container create \
  --name tfstate \
  --account-name stfinrisktf4d9e8d \
  --auth-mode login
```

### ✅ 2. Service Principal Permissions

The Azure DevOps service connection (or your service principal) needs permissions to:

1. **Access Terraform state** (backend storage)
2. **Manage Azure resources** (for infrastructure deployment)

#### A. Terraform State Storage Permissions

**Required for:** Terraform to read/write state files

```bash
# Get your service principal object ID from Azure DevOps or pipeline logs
# Example: dc47ab6c-7fe8-44f3-b019-a9f4ee36981f

# Grant Contributor role on state storage account
az role assignment create \
  --assignee <SERVICE_PRINCIPAL_OBJECT_ID> \
  --role "Contributor" \
  --scope "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/rg-terraform-state/providers/Microsoft.Storage/storageAccounts/stfinrisktf4d9e8d"
```

**✅ Status:** Completed on 2026-02-16
**Service Principal:** dc47ab6c-7fe8-44f3-b019-a9f4ee36981f
**Role:** Contributor
**Scope:** stfinrisktf4d9e8d storage account

#### B. Infrastructure Management Permissions

**Required for:** Terraform to create/manage Azure resources

```bash
# Option 1: Contributor on subscription (most common)
az role assignment create \
  --assignee <SERVICE_PRINCIPAL_OBJECT_ID> \
  --role "Contributor" \
  --subscription <SUBSCRIPTION_ID>

# Option 2: Contributor on specific resource group (more restricted)
az role assignment create \
  --assignee <SERVICE_PRINCIPAL_OBJECT_ID> \
  --role "Contributor" \
  --resource-group rg-finrisk-dev
```

### ✅ 3. Azure DevOps Setup

#### A. Service Connection

1. Go to Azure DevOps → Project Settings → Service connections
2. Create new Azure Resource Manager connection
3. Select "Service principal (automatic)" or "Workload Identity federation (OIDC)"
4. Name: `azure-service-connection`
5. Verify connection works

#### B. Variable Group

1. Go to Azure DevOps → Pipelines → Library
2. Create variable group: `finrisk-dev`
3. Add variables:
   - `terraformStateStorageAccount` = `stfinrisktf4d9e8d`
   - (Optional) `ARM_ACCESS_KEY` = [storage account key] (🔒 secret)

#### C. Environment

1. Go to Azure DevOps → Pipelines → Environments
2. Create environment: `dev-infrastructure`
3. (Optional) Configure approvals and checks

### ✅ 4. Agent Pool

Ensure agent pool `Default` exists and has at least one active agent.

```bash
# Verify agent can run
# Check: Azure DevOps → Project Settings → Agent pools → Default
```

---

## What Terraform Manages

After bootstrap, Terraform manages these resources and permissions:

### 🏗️ Infrastructure Resources

- ✅ Resource Group (`rg-finrisk-dev`)
- ✅ Container Registry (`acrfinriskdev`)
- ✅ Key Vault (`kv-finrisk-dev`)
- ✅ Log Analytics Workspace (`log-finrisk-dev`)
- ✅ Application Insights (`appi-finrisk-dev`)
- ✅ Container App Environment (`cae-finrisk-dev`)
- ✅ Container App (`ca-finrisk-dev`)

### 🔐 Application Role Assignments

Terraform manages these RBAC assignments (in code):

| Principal | Role | Scope | Purpose | File |
|-----------|------|-------|---------|------|
| Deployer Identity | Key Vault Administrator | Key Vault | Manage secrets during deployment | `modules/key-vault/main.tf:158` |
| Container App Identity | AcrPull | Container Registry | Pull Docker images | `modules/container-app/main.tf:336` |
| Container App Identity | Key Vault Secrets User | Key Vault | Read application secrets | `modules/container-app/main.tf:357` |

### ❌ What Terraform Does NOT Manage

These are bootstrap prerequisites (manual setup):

- ❌ Terraform state storage account (`stfinrisktf4d9e8d`)
- ❌ Service principal for Azure DevOps
- ❌ Service principal permissions on state storage
- ❌ Azure DevOps service connections
- ❌ Azure DevOps variable groups
- ❌ Azure DevOps environments

---

## Verification

### Check Bootstrap Prerequisites

```bash
# 1. Verify storage account exists
az storage account show \
  --name stfinrisktf4d9e8d \
  --resource-group rg-terraform-state

# 2. Verify container exists
az storage container show \
  --name tfstate \
  --account-name stfinrisktf4d9e8d

# 3. Verify service principal has permissions
az role assignment list \
  --assignee dc47ab6c-7fe8-44f3-b019-a9f4ee36981f \
  --scope "/subscriptions/94b0c11e-3389-4ca0-b998-a3894e174f3c/resourceGroups/rg-terraform-state/providers/Microsoft.Storage/storageAccounts/stfinrisktf4d9e8d" \
  --output table

# Expected output:
# Principal: dc47ab6c-7fe8-44f3-b019-a9f4ee36981f
# Role: Contributor
```

### Test Terraform Access

```bash
# Test local Terraform can access backend
cd terraform/environments/dev
terraform init -backend-config=backend.hcl
terraform plan

# If successful, backend is properly configured
```

---

## Common Issues

### Issue: "Failed to get existing workspaces"

**Cause:** Service principal lacks permissions on state storage account

**Fix:** Run bootstrap step 2.A (grant Contributor role)

### Issue: "Unauthorized to perform action"

**Cause:** Service principal lacks permissions to manage infrastructure resources

**Fix:** Run bootstrap step 2.B (grant infrastructure permissions)

### Issue: "Backend configuration changed"

**Cause:** Backend config mismatch between local and CI/CD

**Fix:** Ensure `backend.hcl` and pipeline variables match

---

## Security Best Practices

### 1. Least Privilege

Instead of `Contributor` on entire subscription, grant permissions only where needed:

```bash
# More secure: Contributor only on app resource group
az role assignment create \
  --assignee <SP_OBJECT_ID> \
  --role "Contributor" \
  --resource-group rg-finrisk-dev

# Keep separate permission for state storage
az role assignment create \
  --assignee <SP_OBJECT_ID> \
  --role "Contributor" \
  --scope "/subscriptions/.../storageAccounts/stfinrisktf4d9e8d"
```

### 2. Use OIDC Instead of Secrets

Your pipeline already uses OIDC (workload identity federation):

```yaml
# In pipeline - OIDC authentication (secure)
-backend-config=use_oidc=true
-backend-config=oidc_token=***
```

This is more secure than storing service principal secrets.

### 3. Separate Environments

Use separate service principals for dev/staging/prod:

```
dev-sp    → dev-infrastructure environment → rg-finrisk-dev
staging-sp → staging-infrastructure environment → rg-finrisk-staging
prod-sp   → prod-infrastructure environment → rg-finrisk-prod
```

### 4. Regular Audits

```bash
# Audit role assignments quarterly
az role assignment list \
  --assignee <SP_OBJECT_ID> \
  --all \
  --output table
```

---

## Disaster Recovery

### Terraform State Backup

```bash
# Backup state file
az storage blob download \
  --account-name stfinrisktf4d9e8d \
  --container-name tfstate \
  --name finrisk-dev.tfstate \
  --file terraform-state-backup-$(date +%Y%m%d).tfstate

# Enable versioning on storage account
az storage account blob-service-properties update \
  --account-name stfinrisktf4d9e8d \
  --enable-versioning true
```

### State Recovery

If state is corrupted:

```bash
# List versions
az storage blob list \
  --account-name stfinrisktf4d9e8d \
  --container-name tfstate \
  --prefix finrisk-dev.tfstate \
  --include v

# Restore from backup
az storage blob upload \
  --account-name stfinrisktf4d9e8d \
  --container-name tfstate \
  --name finrisk-dev.tfstate \
  --file terraform-state-backup-20260216.tfstate \
  --overwrite
```

---

## Summary

### ✅ Completed Bootstrap Steps

- [x] Backend storage account created
- [x] Service principal has state storage permissions (Contributor)
- [x] Azure DevOps service connection configured
- [x] Variable group `finrisk-dev` created
- [x] Pipeline successfully runs Terraform

### 📋 Recommended Next Steps

1. ✅ Document service principal object ID in team wiki
2. ✅ Set up alerting for role assignment changes
3. ✅ Enable versioning on state storage account
4. ✅ Schedule quarterly permission audits
5. ✅ Create separate service principals for staging/prod

---

## References

- [Terraform Azure Backend](https://developer.hashicorp.com/terraform/language/settings/backends/azurerm)
- [Azure RBAC Built-in Roles](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles)
- [Azure DevOps Service Connections](https://learn.microsoft.com/azure/devops/pipelines/library/service-endpoints)
- [Workload Identity Federation (OIDC)](https://learn.microsoft.com/azure/devops/pipelines/library/connect-to-azure)

---

**Last Updated:** 2026-02-16
**Status:** Bootstrap complete, pipeline operational
