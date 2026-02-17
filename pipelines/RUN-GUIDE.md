# Pipeline Run Guide - FinRisk Platform

## Prerequisites Checklist

Before triggering the pipeline, verify these requirements are met:

### ✅ Azure DevOps Setup

- [ ] Azure DevOps organization exists
- [ ] Azure DevOps project created
- [ ] Pipeline configured from `pipelines/azure-pipelines-infra.yml`
- [ ] GitHub repository connected to Azure DevOps
- [ ] Service connection `azure-service-connection` exists
- [ ] Variable group `finrisk-dev` exists with `terraformStateStorageAccount`
- [ ] Agent pool `Default` is available

### ✅ Azure Resources

- [ ] Backend storage account exists: `rg-terraform-state/stfinrisktf4d9e8d`
- [ ] Service principal has permissions (or using Managed Identity)
- [ ] Azure subscription accessible

---

## Option 1: Trigger via Git Push (Recommended)

### Method A: Make a Documentation Change

This is the **safest** way to trigger the pipeline - it won't change infrastructure.

```bash
# 1. Create a small documentation update in terraform/
echo "# Testing pipeline trigger - $(date)" >> terraform/environments/dev/PIPELINE_TEST.md

# 2. Commit and push
git add terraform/environments/dev/PIPELINE_TEST.md
git commit -m "test: trigger infrastructure pipeline"
git push origin main
```

**Result:** Pipeline will trigger automatically within 30 seconds

### Method B: Update Pipeline Metadata

```bash
# Add a comment to the pipeline file
sed -i.bak '8 a\# Pipeline test run - '"$(date +%Y-%m-%d)" pipelines/azure-pipelines-infra.yml

# Commit and push
git add pipelines/azure-pipelines-infra.yml
git commit -m "test: pipeline validation run"
git push origin main
```

---

## Option 2: Trigger via Pull Request

This will run **ONLY the Plan stage** (no Apply).

```bash
# 1. Create a feature branch
git checkout -b test/pipeline-validation

# 2. Make a change
echo "# PR test - $(date)" >> terraform/environments/dev/PR_TEST.md
git add terraform/environments/dev/PR_TEST.md
git commit -m "test: validate terraform via PR"

# 3. Push branch
git push origin test/pipeline-validation

# 4. Create PR on GitHub
# Go to: https://github.com/sachajw/carreer-pollinate-assessment/compare/test/pipeline-validation
```

**Result:** Pipeline runs Plan stage only (safe for testing)

---

## Option 3: Manual Trigger (Azure DevOps UI)

If your pipeline supports manual triggers:

1. Open Azure DevOps
2. Navigate to: **Pipelines** → **FinRisk-IaC-Terraform**
3. Click **Run pipeline**
4. Select branch: `main`
5. Click **Run**

---

## Option 4: Trigger via Azure CLI

If you have Azure DevOps CLI installed:

```bash
# Install Azure DevOps extension (if not installed)
az extension add --name azure-devops

# Login
az devops login

# Set defaults
az devops configure --defaults organization=https://dev.azure.com/YOUR_ORG project=YOUR_PROJECT

# List pipelines
az pipelines list --output table

# Trigger pipeline by name
az pipelines run --name "FinRisk-IaC-Terraform"

# Or trigger by ID
az pipelines run --id PIPELINE_ID
```

---

## What Happens During Pipeline Run

### Stage 1: Plan (Auto)

```
1. Checkout code from GitHub
2. Install Terraform 1.7.0
3. Initialize Terraform with Azure backend
4. Validate Terraform configuration
5. Generate plan (tfplan file)
6. Publish plan artifact
```

**Duration:** ~2-3 minutes
**Creates:** Plan file (no Azure resources changed)

### Stage 2: Apply (Conditional)

Only runs if:
- Plan stage succeeded
- Running on `main` branch
- May require manual approval (check environment settings)

```
1. Download plan artifact
2. Initialize Terraform
3. Apply plan to Azure
4. Save outputs as artifact
```

**Duration:** ~5-15 minutes
**Creates:** Real Azure infrastructure changes

---

## Monitoring the Pipeline

### Azure DevOps UI

1. Go to: https://dev.azure.com/YOUR_ORG/YOUR_PROJECT/_build
2. Find your pipeline run
3. Click to see live logs
4. Monitor each stage

### Via Azure CLI

```bash
# List recent runs
az pipelines runs list --pipeline-name "FinRisk-IaC-Terraform" --top 5

# Show specific run
az pipelines runs show --id RUN_ID

# Show logs
az pipelines runs show --id RUN_ID --open
```

### Check via Git Commit Status

After pushing, check commit status on GitHub:

```bash
# View commit on GitHub
git log --oneline -1
# Copy commit SHA and visit:
# https://github.com/sachajw/carreer-pollinate-assessment/commit/COMMIT_SHA
```

---

## Expected Output

### Successful Plan Stage

```
✓ Terraform Init completed
✓ Terraform Validate passed
✓ Terraform Plan generated
  - No changes needed (infrastructure matches state)
  OR
  - X resources to add/change/destroy
✓ Plan artifact published
```

### Successful Apply Stage

```
✓ Plan artifact downloaded
✓ Terraform Init completed
✓ Terraform Apply completed
  - Applied X changes
✓ Outputs saved
```

---

## Troubleshooting

### Issue: Pipeline doesn't trigger

**Check:**
```bash
# Verify remote is correct
git remote -v

# Verify push succeeded
git push origin main -v

# Check Azure DevOps connection
# Visit: https://dev.azure.com/YOUR_ORG/YOUR_PROJECT/_settings/boards-external-integration
```

### Issue: Pipeline fails at Plan stage

**Common causes:**
1. Backend storage account not accessible
2. Service connection expired
3. Variable group missing
4. Terraform syntax error

**Fix:**
```bash
# Validate Terraform locally first
cd terraform/environments/dev
terraform init -backend-config=backend.hcl
terraform validate
terraform plan
```

### Issue: Pipeline fails at Apply stage

**Common causes:**
1. Azure quota exceeded
2. Resource naming conflicts
3. Permissions issue
4. Network timeout

**Fix:**
Check Azure DevOps logs and review Terraform error messages.

---

## Safety Checks

### Before Running in Production

- [ ] Review Terraform plan output carefully
- [ ] Verify no unexpected deletions
- [ ] Check estimated costs
- [ ] Confirm change window
- [ ] Backup state file
- [ ] Have rollback plan ready

### Dry Run Validation

Before pushing to trigger pipeline:

```bash
# Run local validation
bash pipelines/test-infra-pipeline.sh

# Review plan
cd terraform/environments/dev
terraform plan

# Run tests
cd ../../../terraform/tests
bash run-tests.sh --short
```

---

## Quick Command Reference

### Safe Pipeline Trigger (Documentation Change)

```bash
echo "# Pipeline test - $(date)" >> terraform/environments/dev/PIPELINE_TEST.md
git add terraform/environments/dev/PIPELINE_TEST.md
git commit -m "test: trigger infrastructure pipeline"
git push origin main
```

### Check Pipeline Status

```bash
# Via Azure CLI
az pipelines runs list --top 1 --output table

# Via Git
git log --oneline -1
# Then check commit status on GitHub
```

### Rollback if Needed

```bash
# Revert last commit
git revert HEAD
git push origin main

# Or force revert (use with caution)
git reset --hard HEAD~1
git push origin main --force
```

---

## Next Steps After Pipeline Run

1. **Monitor Pipeline**
   - Watch Azure DevOps logs
   - Verify each stage completes

2. **Review Changes**
   - Check Terraform outputs
   - Verify resources in Azure Portal

3. **Test Application**
   - Check Container App health endpoint
   - Verify logs in Application Insights

4. **Document Results**
   - Save pipeline run URL
   - Note any issues encountered

---

## Support

- **Pipeline Issues:** Check Azure DevOps logs
- **Terraform Issues:** Review plan output
- **Azure Issues:** Check Activity Log in Portal
- **Local Testing:** Use `test-infra-pipeline.sh`

