# Fix Storage Account Permissions

## Issue

```
Error: Failed to get existing workspaces
Status=403 Code="AuthorizationFailed"
Message="The client '***' with object id 'dc47ab6c-7fe8-44f3-b019-a9f4ee36981f'
does not have authorization to perform action
'Microsoft.Storage/storageAccounts/listKeys/action' over scope
'/subscriptions/.../resourceGroups/rg-terraform-state/providers/Microsoft.Storage/storageAccounts/stfinrisktf4d9e8d'"
```

## Root Cause

The Azure DevOps service connection doesn't have permission to access the Terraform state storage account.

**Service Principal Object ID:** `dc47ab6c-7fe8-44f3-b019-a9f4ee36981f`
**Storage Account:** `stfinrisktf4d9e8d`
**Resource Group:** `rg-terraform-state`

---

## Solution: Grant Storage Permissions

### Option 1: Using Azure Portal (Recommended - 3 minutes)

#### Step 1: Find Service Principal Name

1. **Open Azure Portal**
   ```
   https://portal.azure.com
   ```

2. **Go to Azure Active Directory** (Entra ID)
   - Search for "Azure Active Directory"

3. **Navigate to Enterprise Applications**
   - Left menu → Enterprise Applications

4. **Search by Object ID**
   - Paste: `dc47ab6c-7fe8-44f3-b019-a9f4ee36981f`
   - Note the **Display Name** (this is your service principal)

#### Step 2: Grant Storage Permissions

1. **Navigate to Storage Account**
   ```
   Portal → Storage accounts → stfinrisktf4d9e8d
   ```

2. **Go to Access Control (IAM)**
   - Left menu → Access Control (IAM)

3. **Click "Add" → "Add role assignment"**

4. **Select Role**
   - **Option A (More Secure):** Storage Blob Data Contributor
   - **Option B (Traditional):** Contributor
   - Click "Next"

5. **Assign Access To**
   - Select "User, group, or service principal"
   - Click "+ Select members"

6. **Search for Service Principal**
   - Paste the display name from Step 1
   - Select it
   - Click "Select"

7. **Review + Assign**
   - Click "Review + assign"
   - Wait for confirmation (~30 seconds)

---

### Option 2: Using Azure CLI (Faster - 1 minute)

```bash
# 1. Get service principal details
az ad sp show --id dc47ab6c-7fe8-44f3-b019-a9f4ee36981f

# 2. Grant "Storage Blob Data Contributor" role
az role assignment create \
  --assignee dc47ab6c-7fe8-44f3-b019-a9f4ee36981f \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/94b0c11e-3389-4ca0-b998-a3894e174f3c/resourceGroups/rg-terraform-state/providers/Microsoft.Storage/storageAccounts/stfinrisktf4d9e8d"

# 3. Verify assignment
az role assignment list \
  --assignee dc47ab6c-7fe8-44f3-b019-a9f4ee36981f \
  --scope "/subscriptions/94b0c11e-3389-4ca0-b998-a3894e174f3c/resourceGroups/rg-terraform-state/providers/Microsoft.Storage/storageAccounts/stfinrisktf4d9e8d" \
  --output table
```

**Expected Output:**
```
Principal                              Role                         Scope
-------------------------------------  ---------------------------  --------
dc47ab6c-7fe8-44f3-b019-a9f4ee36981f  Storage Blob Data Contributor  /subscriptions/.../stfinrisktf4d9e8d
```

---

### Option 3: Grant Broader Permissions (Less Secure)

If the above doesn't work, you may need broader permissions:

```bash
# Grant Contributor role on the entire resource group
az role assignment create \
  --assignee dc47ab6c-7fe8-44f3-b019-a9f4ee36981f \
  --role "Contributor" \
  --resource-group rg-terraform-state
```

---

## Alternative: Use Storage Account Key

Instead of using OIDC/service principal, use a storage account access key.

### Step 1: Get Storage Account Key

```bash
# Get storage account key
az storage account keys list \
  --account-name stfinrisktf4d9e8d \
  --resource-group rg-terraform-state \
  --query '[0].value' \
  --output tsv
```

### Step 2: Add to Variable Group

1. **Go to Azure DevOps**
   ```
   https://dev.azure.com/YOUR_ORG/YOUR_PROJECT/_library?itemType=VariableGroups
   ```

2. **Edit Variable Group: `finrisk-dev`**

3. **Add New Variable**
   - Name: `ARM_ACCESS_KEY`
   - Value: [Paste the key from Step 1]
   - **Important:** Click the 🔒 lock icon to make it secret

4. **Save**

### Step 3: Update Pipeline

Add this environment variable to the Terraform tasks:

```yaml
# In azure-pipelines-infra.yml
# Add to each TerraformTaskV4@4 task:

- task: TerraformTaskV4@4
  displayName: 'Terraform Init'
  inputs:
    provider: 'azurerm'
    command: 'init'
    workingDirectory: '$(terraformWorkingDirectory)'
    backendServiceArm: '$(azureSubscription)'
    backendAzureRmResourceGroupName: 'rg-terraform-state'
    backendAzureRmStorageAccountName: '$(terraformStateStorageAccount)'
    backendAzureRmContainerName: 'tfstate'
    backendAzureRmKey: 'finrisk-$(environmentName).tfstate'
  env:
    ARM_ACCESS_KEY: $(ARM_ACCESS_KEY)  # ← Add this
```

⚠️ **Note:** This is less secure than OIDC but works immediately.

---

## Recommended Approach

### For Production:
✅ **Use Option 1 or 2** - Grant RBAC permissions (more secure)

### For Quick Testing:
⚠️ **Use Option 3** - Storage account key (works immediately, less secure)

---

## After Granting Permissions

### Wait for Propagation

Azure RBAC permissions can take 5-10 minutes to propagate.

**Quick check:**
```bash
# Test if service principal can access storage
az storage blob list \
  --account-name stfinrisktf4d9e8d \
  --container-name tfstate \
  --auth-mode login
```

### Re-run Pipeline

1. **Option A: Trigger via commit**
   ```bash
   echo "# Permissions granted - $(date)" >> terraform/environments/dev/PIPELINE_RUN.md
   git add terraform/environments/dev/PIPELINE_RUN.md
   git commit -m "chore: retry pipeline after storage permissions"
   git push origin main
   ```

2. **Option B: Manual re-run**
   - Go to failed pipeline in Azure DevOps
   - Click "Run new"

---

## Verification

### Pipeline Should Show:

```
✅ Terraform Init
   Initializing the backend...
   Initializing modules...
   Terraform has been successfully initialized!
```

### If Still Failing:

Check these:

1. **Permissions applied correctly?**
   ```bash
   az role assignment list \
     --assignee dc47ab6c-7fe8-44f3-b019-a9f4ee36981f \
     --all
   ```

2. **Storage account exists?**
   ```bash
   az storage account show \
     --name stfinrisktf4d9e8d \
     --resource-group rg-terraform-state
   ```

3. **Terraform state container exists?**
   ```bash
   az storage container show \
     --name tfstate \
     --account-name stfinrisktf4d9e8d
   ```

---

## Common Issues

### Issue: "Role assignment already exists"

This is fine - permissions are already granted. Wait 5-10 minutes for propagation.

### Issue: "Cannot find principal"

The service principal might be in a different tenant. Verify:

```bash
az ad sp show --id dc47ab6c-7fe8-44f3-b019-a9f4ee36981f
```

### Issue: "Forbidden"

You may not have permission to grant roles. Ask your Azure subscription admin.

---

## Required Roles Summary

The service principal needs **ONE** of these:

| Role | Scope | Security | Recommended |
|------|-------|----------|-------------|
| Storage Blob Data Contributor | Storage Account | High | ✅ Yes |
| Contributor | Storage Account | Medium | ⚠️ OK |
| Contributor | Resource Group | Low | ❌ No |

**Best Practice:** Use "Storage Blob Data Contributor" on the storage account only.

---

## Quick Commands Reference

```bash
# Grant storage permissions (recommended)
az role assignment create \
  --assignee dc47ab6c-7fe8-44f3-b019-a9f4ee36981f \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/94b0c11e-3389-4ca0-b998-a3894e174f3c/resourceGroups/rg-terraform-state/providers/Microsoft.Storage/storageAccounts/stfinrisktf4d9e8d"

# Verify permissions
az role assignment list \
  --assignee dc47ab6c-7fe8-44f3-b019-a9f4ee36981f \
  --output table

# Re-run pipeline
echo "# Permissions fixed" >> terraform/environments/dev/PIPELINE_RUN.md
git add terraform/environments/dev/PIPELINE_RUN.md
git commit -m "chore: retry after permissions"
git push origin main
```

---

## Next Steps

1. ✅ **Grant permissions** (use Option 1 or 2 above)
2. ⏱️ **Wait 5 minutes** for propagation
3. ▶️ **Re-run pipeline**
4. ✅ **Verify success**

