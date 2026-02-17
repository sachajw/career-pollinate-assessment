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
| Container App Identity | AcrPull | Container Registry | Pull Docker images | `modules/container-app/main.tf:360` |
| Container App Identity | Key Vault Secrets User | Key Vault | Read application secrets | `modules/container-app/main.tf:381` |

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

### Issue: "Failed to get existing workspaces" (403 AuthorizationFailed)

**Error:**
```
Error: Failed to get existing workspaces
Status=403 Code="AuthorizationFailed"
Message="The client '***' with object id 'dc47ab6c-...' does not have authorization
to perform action 'Microsoft.Storage/storageAccounts/listKeys/action'"
```

**Cause:** Service principal lacks permissions on the Terraform state storage account.

**Fix Option A — Storage Blob Data Contributor (recommended, least privilege):**

```bash
# Replace with your service principal object ID (from pipeline logs)
SP_OBJECT_ID="dc47ab6c-7fe8-44f3-b019-a9f4ee36981f"

az role assignment create \
  --assignee "$SP_OBJECT_ID" \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/94b0c11e-3389-4ca0-b998-a3894e174f3c/resourceGroups/rg-terraform-state/providers/Microsoft.Storage/storageAccounts/stfinrisktf4d9e8d"

# Verify
az role assignment list --assignee "$SP_OBJECT_ID" --output table
```

**Fix Option B — via Azure Portal:**
1. Portal → Storage accounts → `stfinrisktf4d9e8d` → Access Control (IAM)
2. Add → Add role assignment → **Storage Blob Data Contributor**
3. Assign to the service principal (search by object ID)

**Fix Option C — Storage Account Key (quick fallback, less secure):**
```bash
# Get storage account key
az storage account keys list \
  --account-name stfinrisktf4d9e8d \
  --resource-group rg-terraform-state \
  --query '[0].value' --output tsv
# Add as secret variable ARM_ACCESS_KEY in Azure DevOps variable group
```

**After granting:** RBAC takes 5–10 minutes to propagate. Verify access:
```bash
az storage blob list \
  --account-name stfinrisktf4d9e8d \
  --container-name tfstate \
  --auth-mode login
```

### Issue: "Unauthorized to perform action"

**Cause:** Service principal lacks permissions to manage infrastructure resources

**Fix:** Run bootstrap step 2.B (grant infrastructure permissions)

### Issue: "Backend configuration changed"

**Cause:** Backend config mismatch between local and CI/CD

**Fix:** Ensure `backend.hcl` and pipeline variables match

### Issue: "Role assignment already exists"

This is not an error — permissions are already granted. Wait 5–10 minutes for propagation.

### Issue: "Cannot find principal"

The service principal may be in a different tenant. Verify:
```bash
az ad sp show --id <object-id>
```

---

## Known Issues & Solutions

Three recurring deployment issues and their recommended fixes.

---

### Issue 1: RBAC Propagation Delay (403 errors after role assignment)

Azure RBAC role assignments take 2–5 minutes to propagate. Resources that depend on fresh RBAC may fail with 403 immediately after assignment.

**Recommended fix — add `time_sleep` after role assignments:**

```hcl
# In modules/container-app/main.tf or environments/dev/main.tf

resource "time_sleep" "wait_for_rbac_propagation" {
  depends_on = [
    azurerm_role_assignment.deployer,
    azurerm_role_assignment.acr_pull,
    azurerm_role_assignment.keyvault_secrets_user,
  ]
  create_duration = "120s"
}

resource "azurerm_container_app" "this" {
  # ... existing config ...
  depends_on = [time_sleep.wait_for_rbac_propagation]
}
```

Add to `environments/dev/versions.tf`:
```hcl
time = {
  source  = "hashicorp/time"
  version = "~> 0.9"
}
```

**Alternative — retry logic via `local-exec`:**
```hcl
resource "null_resource" "wait_for_storage_rbac" {
  depends_on = [azurerm_role_assignment.storage_contributor]

  provisioner "local-exec" {
    command = <<-EOT
      for i in {1..5}; do
        if az storage container list --account-name ${var.storage_account_name} --auth-mode login &>/dev/null; then
          echo "RBAC propagated"; exit 0
        fi
        echo "Retry $i/5: waiting 30s..."; sleep 30
      done
    EOT
  }
}
```

---

### Issue 2: Missing Provider Registration (MissingSubscriptionRegistration)

Azure resource providers must be registered for a subscription before use.

**Recommended fix — auto-register via Terraform:**

```hcl
# Create: terraform/environments/dev/providers-setup.tf

resource "azurerm_resource_provider_registration" "container_apps" {
  name = "Microsoft.App"
}
resource "azurerm_resource_provider_registration" "container_registry" {
  name = "Microsoft.ContainerRegistry"
}
resource "azurerm_resource_provider_registration" "key_vault" {
  name = "Microsoft.KeyVault"
}
resource "azurerm_resource_provider_registration" "operational_insights" {
  name = "Microsoft.OperationalInsights"
}
resource "azurerm_resource_provider_registration" "insights" {
  name = "Microsoft.Insights"
}
resource "azurerm_resource_provider_registration" "storage" {
  name = "Microsoft.Storage"
}

resource "time_sleep" "wait_for_providers" {
  depends_on = [
    azurerm_resource_provider_registration.container_apps,
    azurerm_resource_provider_registration.container_registry,
    azurerm_resource_provider_registration.key_vault,
    azurerm_resource_provider_registration.operational_insights,
    azurerm_resource_provider_registration.insights,
    azurerm_resource_provider_registration.storage,
  ]
  create_duration = "60s"
}
```

**Alternative — pre-flight check script (`terraform/scripts/preflight-check.sh`):**

```bash
#!/bin/bash
set -e

PROVIDERS=(
  "Microsoft.App"
  "Microsoft.ContainerRegistry"
  "Microsoft.KeyVault"
  "Microsoft.OperationalInsights"
  "Microsoft.Insights"
  "Microsoft.Storage"
)

for PROVIDER in "${PROVIDERS[@]}"; do
  STATE=$(az provider show --namespace "$PROVIDER" --query registrationState -o tsv)
  if [ "$STATE" != "Registered" ]; then
    az provider register --namespace "$PROVIDER" --wait
  fi
done
```

---

### Issue 3: Container Registry Circular Dependency

System-assigned identity for a Container App requires the app to exist before you can grant it ACR pull access — but the app can't pull images without that access. Break this cycle with a **user-assigned managed identity**.

**Recommended fix — user-assigned identity module:**

```hcl
# Step 1: Create identity first
resource "azurerm_user_assigned_identity" "app" {
  name                = "id-${local.naming_prefix}"
  resource_group_name = var.resource_group_name
  location            = var.location
}

# Step 2: Grant ACR pull to identity (before Container App exists)
resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

resource "time_sleep" "wait_for_rbac" {
  depends_on      = [azurerm_role_assignment.acr_pull]
  create_duration = "120s"
}

# Step 3: Container App uses user-assigned identity
resource "azurerm_container_app" "this" {
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }
  registry {
    server   = var.registry_server
    identity = azurerm_user_assigned_identity.app.id
  }
  depends_on = [time_sleep.wait_for_rbac]
}
```

**Correct deployment order:**
```
1. Provider Registration
2. Resource Group
3. Container Registry
4. User-Assigned Managed Identity
5. RBAC Assignments (ACR + Key Vault)
6. Wait for RBAC Propagation (120s)
7. Container App
```

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
