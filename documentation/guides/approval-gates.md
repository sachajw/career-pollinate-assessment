# Manual Approval Gate Setup

## Overview

Add a **manual approval gate** before Terraform Apply to ensure human operators review and approve infrastructure changes.

**Current Status:** Pipeline structure ready (uses environment `dev-infrastructure`)
**Action Required:** Configure approval gate in Azure DevOps

---

## Quick Setup (5 minutes)

### Step 1: Open Environment Settings

1. **Go to Azure DevOps**
   ```
   https://dev.azure.com/YOUR_ORG/YOUR_PROJECT/_environments
   ```

2. **Find or create environment:** `dev-infrastructure`
   - If it doesn't exist, it will be created automatically on first pipeline run
   - Or click "New environment" to create it now

3. **Click on the environment name** to open settings

### Step 2: Add Approval Gate

1. **Click on the three dots (⋯)** in the top right

2. **Select "Approvals and checks"**

3. **Click "+ Add new"** (or **"Approvals"** if it's the first check)

4. **Configure Approvers:**
   - **Approvers:** Add users/groups who can approve
     - Example: Your email, team members
     - Recommended: At least 2 approvers for production

   - **Advanced:**
     - ✅ **Allow approvers to approve their own runs**: Uncheck (for safety)
     - ✅ **Require a minimum number of reviewers**: 1 (or 2 for production)
     - **Timeout**: 30 days (default is fine)
     - **Instructions to approvers:**
       ```
       Review Terraform plan output before approving.

       Check:
       - No unexpected deletions
       - Resource changes are expected
       - Security configurations are correct

       Deny if anything looks suspicious.
       ```

5. **Click "Create"**

### Step 3: Test the Approval Gate

1. **Trigger the pipeline** (push a commit or re-run)

2. **Plan stage completes automatically**

3. **Apply stage waits for approval:**
   ```
   Waiting for approval from: [Your Name]

   Review plan and approve to continue...
   ```

4. **Review the Terraform plan output**
   - Click "View logs" on Plan stage
   - Review what resources will change

5. **Approve or Reject:**
   - Click "Review" button
   - Add comment (optional but recommended)
   - Click "Approve" or "Reject"

---

## How It Works

### Pipeline Flow with Approval Gate

```
┌──────────────────────────────────────────────────────────┐
│  Stage 1: Plan (Automatic)                               │
│  ✓ Terraform Init                                        │
│  ✓ Terraform Validate                                    │
│  ✓ Terraform Plan                                        │
│  ✓ Publish Plan Artifact                                 │
└──────────────────────────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────┐
│  ⏸️  APPROVAL REQUIRED                                    │
│                                                           │
│  Pipeline paused waiting for human approval              │
│  Approvers: [Your Team]                                  │
│                                                           │
│  ✅ Approve    ❌ Reject                                  │
└──────────────────────────────────────────────────────────┘
                         ↓ (After Approval)
┌──────────────────────────────────────────────────────────┐
│  Stage 2: Apply (After Approval)                         │
│  ✓ Download Plan                                         │
│  ✓ Terraform Init                                        │
│  ✓ Terraform Apply                                       │
│  ✓ Save Outputs                                          │
└──────────────────────────────────────────────────────────┘
```

### Key Points

- ✅ **Plan stage runs automatically** - See proposed changes
- ⏸️ **Apply stage waits** - Manual review required
- ✅ **Approvers notified** - Email notification sent
- 🔒 **No changes until approved** - Infrastructure is safe
- 📝 **Audit trail** - Who approved what and when

---

## Current Pipeline Configuration

Your pipeline at `pipelines/azure-pipelines-infra.yml` already has:

```yaml
- stage: Apply
  displayName: 'Terraform Apply'
  dependsOn: Plan
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
  jobs:
    - deployment: TerraformApply
      pool: Default
      environment: '$(environmentName)-infrastructure'  # ← Approval gate configured here
      strategy:
        runOnce:
          deploy:
            steps:
              # Terraform apply steps...
```

**Environment:** `dev-infrastructure` (from variable `environmentName: 'dev'`)

---

## Advanced Configuration

### Multiple Environments

Configure different approval requirements per environment:

| Environment | Approvers | Min Reviewers | Timeout |
|-------------|-----------|---------------|---------|
| `dev-infrastructure` | 1 team member | 1 | 7 days |
| `staging-infrastructure` | 1 lead | 1 | 14 days |
| `prod-infrastructure` | 2 leads + manager | 2 | 30 days |

### Branch Policies

Add branch-specific approval requirements:

```yaml
# In pipeline YAML
- stage: Apply
  condition: |
    and(
      succeeded(),
      or(
        eq(variables['Build.SourceBranch'], 'refs/heads/main'),
        eq(variables['Build.SourceBranch'], 'refs/heads/staging')
      )
    )
```

### Approval Timeout

Set custom timeout for approvals:

```yaml
- deployment: TerraformApply
  environment:
    name: '$(environmentName)-infrastructure'
    resourceType: VirtualMachine
  timeoutInMinutes: 1440  # 24 hours
```

### Multiple Check Types

Add additional checks beyond approvals:

1. **Approvals** - Manual human review
2. **Business Hours** - Only allow deployments during work hours
3. **Invoke Azure Function** - Custom validation logic
4. **Query Azure Monitor alerts** - Check for active incidents

---

## Notification Setup

### Email Notifications

Approvers receive email when approval is needed:

**Subject:** `[Azure Pipelines] Approval needed for FinRisk-IaC-Terraform #123`

**Body:**
```
Your approval is required for:
- Pipeline: FinRisk-IaC-Terraform
- Stage: Apply
- Environment: dev-infrastructure

Review and approve: [Link to pipeline]
```

### Slack Integration (Optional)

Connect Azure DevOps to Slack for team notifications:

1. Install Azure Pipelines app in Slack
2. Subscribe to pipeline events
3. Get notifications in team channel

---

## Approval Best Practices

### What to Check Before Approving

1. **Review Terraform Plan Output:**
   ```
   Plan: 0 to add, 1 to change, 0 to destroy
   ```
   - ✅ Adding resources: Expected for new features
   - ⚠️ Changing resources: Verify it's intentional
   - 🚨 Destroying resources: CAREFULLY review - data loss possible!

2. **Check Resource Types:**
   - Adding Container Apps, Key Vaults, etc.? OK
   - Destroying databases or storage? ⚠️ CAUTION
   - Modifying security settings? Double-check

3. **Verify Scope:**
   - Changes only in expected resource group?
   - No unexpected resources affected?
   - Correct environment (dev vs prod)?

4. **Security Review:**
   - No public IP exposure
   - Firewall rules are restrictive
   - Secrets go to Key Vault (not plaintext)
   - RBAC follows least privilege

### When to Reject

❌ **Reject and investigate if:**
- Unexpected resource deletions
- Changes to production database
- Public IP exposure
- Overly permissive security rules
- Resources in wrong subscription/region
- Plan output doesn't match the change request

### Approval Comments

Add context when approving:

```
✅ Approved

Reviewed Terraform plan:
- Adding new Container App revision
- Security settings verified
- No data loss risk
- Matches change ticket #456

Approved by: [Your Name]
Date: 2026-02-16
```

---

## Testing Approval Gate

### Test Scenario 1: Normal Approval

1. Push infrastructure change
2. Wait for Plan stage to complete
3. Review plan output
4. Approve Apply stage
5. Verify infrastructure updated

### Test Scenario 2: Rejection

1. Push change
2. Review plan
3. Reject with reason: "Unexpected resource deletion detected"
4. Pipeline fails at Apply stage
5. Investigate issue, fix, re-run

### Test Scenario 3: Timeout

1. Push change
2. Don't approve within timeout (default: 30 days)
3. Pipeline automatically fails
4. Can re-run and approve

---

## Audit Trail

All approvals are logged and auditable:

### View Approval History

1. Go to environment: `dev-infrastructure`
2. Click "Deployments" tab
3. See all deployments with approval status

### Audit Information Includes:

- Who approved/rejected
- When (timestamp)
- Comments provided
- Plan output at time of approval
- Git commit SHA
- Pipeline run number

### Compliance Reporting

Export approval history for compliance:

```bash
# Via Azure CLI
az pipelines runs list \
  --project YOUR_PROJECT \
  --pipeline-ids PIPELINE_ID \
  --query "[].{id:id,status:status,finishTime:finishTime,approvedBy:approvedBy}" \
  --output table
```

---

## Troubleshooting

### Issue: Can't find environment

**Cause:** Environment not created yet

**Fix:** Run pipeline once, environment will be auto-created

### Issue: Approval not triggering

**Cause:** Environment name mismatch

**Fix:** Verify environment name matches: `dev-infrastructure`

```yaml
# Check in pipeline YAML
environment: '$(environmentName)-infrastructure'

# Check variable
environmentName: 'dev'

# Expected environment: dev-infrastructure
```

### Issue: Wrong people can approve

**Cause:** Incorrect approvers configured

**Fix:** Update environment approvers list in Azure DevOps

### Issue: Approval emails not received

**Cause:** Email notifications disabled

**Fix:** Check Azure DevOps notification settings:
1. User Settings → Notifications
2. Enable "A deployment pending approval"

---

## Security Considerations

### Separation of Duties

**Best Practice:** Approvers should NOT be the same people who write infrastructure code

```
Developer → Writes Terraform code → Commits
   ↓
Pipeline → Runs Plan automatically
   ↓
Operator/Lead → Reviews plan → Approves
   ↓
Pipeline → Runs Apply → Updates infrastructure
```

### Approval Permissions

Configure who can approve in environment settings:

- **Dev environment:** Any team member
- **Staging environment:** Team leads only
- **Production environment:** Multiple leads + manager

### Bypass Protection

⚠️ **Do NOT allow:**
- Approval bypass
- Self-approval of own changes (in production)
- Same person for both dev and approval

---

## Quick Reference

### Enable Approval Gate

```
Azure DevOps → Environments → dev-infrastructure →
Approvals and checks → Add approval
```

### Required Settings

- **Approvers:** [Your team]
- **Min reviewers:** 1 (or 2 for production)
- **Allow self-approve:** ❌ Unchecked
- **Timeout:** 30 days

### Pipeline Behavior

- **Plan stage:** ✅ Runs automatically
- **Apply stage:** ⏸️ Waits for approval
- **After approval:** ✅ Runs automatically
- **After rejection:** ❌ Fails (can re-run)

---

## Summary

✅ **Current Status:**
- Pipeline structure: Ready (uses environment)
- Approval gate: Not yet configured

✅ **Next Steps:**
1. Go to Azure DevOps Environments
2. Configure approval on `dev-infrastructure`
3. Add yourself as approver
4. Test by triggering pipeline

✅ **Benefits:**
- Human review before changes
- Prevent accidental deletions
- Audit trail for compliance
- Safety gate for production

---

**Setup Time:** 5 minutes
**Impact:** High security improvement
**Recommended:** ✅ Yes, especially for production

