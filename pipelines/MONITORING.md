# Pipeline Monitoring - Active Run

## Pipeline Triggered ✅

**Date:** 2026-02-16
**Commit:** 5dd0876
**Branch:** main
**Trigger:** Git push to terraform/ directory

---

## Pipeline Details

**Name:** FinRisk-IaC-Terraform
**File:** `pipelines/azure-pipelines-infra.yml`
**Environment:** dev

---

## How to Monitor

### Option 1: Azure DevOps Portal (Recommended)

1. **Open Azure DevOps**
   ```
   https://dev.azure.com/YOUR_ORG/YOUR_PROJECT/_build
   ```

2. **Find Latest Run**
   - Look for build with commit message: "test: trigger infrastructure pipeline with dry run validation"
   - Build number format: `FinRisk-IaC-Terraform-YYYYMMDD-HHMM.r`

3. **Watch Live Logs**
   - Click on the pipeline run
   - Select stage (Plan or Apply)
   - View real-time console output

### Option 2: GitHub Commit Status

1. **View Commit**
   ```bash
   # Copy commit SHA
   git log --oneline -1
   ```

2. **Check on GitHub**
   ```
   https://github.com/sachajw/career-pollinate-assessment/commit/5dd0876
   ```

3. **Look for Checks**
   - Azure Pipelines check should appear
   - Status: ⏳ Pending → ✅ Success / ❌ Failed

### Option 3: Azure CLI

```bash
# Install Azure DevOps extension (if needed)
az extension add --name azure-devops

# Login
az devops login

# Configure defaults
az devops configure --defaults \
  organization=https://dev.azure.com/YOUR_ORG \
  project=YOUR_PROJECT

# List recent runs
az pipelines runs list --top 5 --output table

# Show specific run (get ID from above)
az pipelines runs show --id RUN_ID

# Follow logs in real-time
az pipelines runs show --id RUN_ID --open
```

---

## Expected Timeline

| Stage | Duration | Status |
|-------|----------|--------|
| **Queue** | 10-30 sec | Pipeline enters queue |
| **Plan - Checkout** | 10-20 sec | Clone repository |
| **Plan - Terraform Init** | 15-30 sec | Initialize backend |
| **Plan - Terraform Validate** | 5-10 sec | Validate configuration |
| **Plan - Terraform Plan** | 30-60 sec | Generate plan |
| **Plan - Publish Artifact** | 5-10 sec | Save plan file |
| **Apply - Wait** | - | Conditional (main branch only) |
| **Apply - Download** | 5-10 sec | Get plan artifact |
| **Apply - Terraform Init** | 15-30 sec | Re-initialize |
| **Apply - Terraform Apply** | 30-90 sec | Apply changes |
| **Apply - Save Outputs** | 5-10 sec | Export outputs |

**Total Expected Duration:** ~3-5 minutes (Plan + Apply)

---

## What to Look For

### Stage 1: Plan ✓

**Success Indicators:**
```
✓ Terraform initialized successfully
✓ Terraform configuration is valid
✓ Terraform plan generated
✓ Plan artifact published
```

**Expected Plan Output:**
Since infrastructure is already deployed, plan should show:
```
No changes. Your infrastructure matches the configuration.
```

Or minimal output changes:
```
Changes to Outputs:
  ~ container_app_fqdn = "..." -> "..." (revision updated)
```

### Stage 2: Apply ✓

**Runs only if:**
- Plan stage succeeded
- Running on `main` branch
- Environment approval granted (if configured)

**Success Indicators:**
```
✓ Plan artifact downloaded
✓ Terraform initialized
✓ Apply complete! Resources: 0 added, 0 changed, 0 destroyed
✓ Outputs saved
```

---

## Troubleshooting

### Pipeline Doesn't Start

**Wait 1-2 minutes.** Azure DevOps may take time to detect the push.

**Verify trigger:**
```bash
# Check commit is on main
git log origin/main --oneline -1

# Verify files changed match trigger paths
git show --name-only HEAD
```

**Expected changed files:**
- `terraform/environments/dev/PIPELINE_RUN.md` ✓ (matches terraform/**)
- Other files (don't block trigger)

### Plan Stage Fails

**Common Issues:**

1. **Backend not accessible**
   ```
   Error: Failed to get existing workspaces
   ```
   **Fix:** Verify storage account `stfinrisktf4d9e8d` exists and is accessible

2. **Service connection expired**
   ```
   Error: Azure authentication failed
   ```
   **Fix:** Refresh service connection in Azure DevOps

3. **Variable group missing**
   ```
   Error: Variable 'terraformStateStorageAccount' is not defined
   ```
   **Fix:** Verify variable group `finrisk-dev` exists

4. **Terraform validation error**
   ```
   Error: Invalid configuration
   ```
   **Fix:** Check Terraform syntax locally first

### Apply Stage Fails

**Common Issues:**

1. **Manual approval timeout**
   ```
   Waiting for approval...
   ```
   **Fix:** Approve in Azure DevOps environment settings

2. **Azure quota exceeded**
   ```
   Error: QuotaExceeded
   ```
   **Fix:** Increase quota or use different region

3. **Resource conflict**
   ```
   Error: Resource already exists
   ```
   **Fix:** Check for manual Azure Portal changes

---

## After Pipeline Completes

### 1. Verify Success

**Azure DevOps:**
- ✅ Both stages show green checkmarks
- ✅ No errors in logs

**GitHub:**
- ✅ Commit shows green checkmark
- ✅ Azure Pipelines check passed

### 2. Check Outputs

**View Terraform outputs:**
```bash
# In Azure DevOps, download terraform-outputs artifact
# Or check logs for output section
```

**Key outputs to verify:**
- `container_app_url` - Application URL
- `container_registry_login_server` - ACR endpoint
- `key_vault_uri` - Key Vault URL
- `quick_start_commands` - Helper commands

### 3. Test Infrastructure

```bash
# Test Container App health endpoint
curl https://YOUR_APP_URL/health

# Verify Application Insights
az monitor app-insights component show \
  --app appi-finrisk-dev \
  --resource-group rg-finrisk-dev

# Check Container App status
az containerapp show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query "properties.runningStatus"
```

### 4. Review Changes

**What changed:**
- ✅ 7 new files committed (documentation + test scripts)
- ✅ Azure infrastructure validated
- ✅ Terraform state confirmed up-to-date

**Infrastructure impact:**
- ℹ️ No infrastructure changes (as expected)
- ℹ️ Only output values updated (FQDN revision)

---

## Security Notice

⚠️ **GitHub Dependabot Alert**

GitHub detected 14 vulnerabilities:
- 2 Critical
- 4 High
- 8 Moderate

**View details:**
```
https://github.com/sachajw/career-pollinate-assessment/security/dependabot
```

**Recommendation:** Address these after pipeline completes successfully.

---

## Next Steps

### After Pipeline Success

1. **Document Results**
   - Save pipeline run URL
   - Note execution time
   - Capture any warnings

2. **Run Application Tests** (if app deployed)
   ```bash
   cd app
   # Run health checks and smoke tests
   ```

3. **Update Documentation**
   - Add pipeline run results to PIPELINE_RUN.md
   - Document any issues encountered

4. **Address Security Issues**
   - Review Dependabot alerts
   - Update vulnerable dependencies
   - Re-run pipeline after fixes

### If Pipeline Fails

1. **Review Logs**
   - Check Azure DevOps console output
   - Identify failure stage and error message

2. **Validate Locally**
   ```bash
   bash pipelines/test-infra-pipeline.sh
   ```

3. **Fix Issues**
   - Apply fixes based on error messages
   - Re-run local validation

4. **Retry Pipeline**
   - Push fix commit
   - Or manually re-run in Azure DevOps

---

## Quick Reference

```bash
# View latest commit
git log --oneline -1

# Check GitHub commit status
open "https://github.com/sachajw/career-pollinate-assessment/commit/5dd0876"

# Azure DevOps (update with your org/project)
open "https://dev.azure.com/YOUR_ORG/YOUR_PROJECT/_build"

# Monitor via CLI
az pipelines runs list --top 1 --output table
```

---

**Pipeline triggered at:** $(date)
**Monitoring status:** Active
**Expected completion:** 3-5 minutes from trigger
