# Install Terraform Extension - Step by Step

## Overview

Install the official Microsoft Terraform extension to fix your pipeline.

**Time Required:** 5 minutes
**Prerequisites:** Azure DevOps admin permissions (or request admin to do this)

---

## Step 1: Open Terraform Extension Page

Click this link:

**👉 https://marketplace.visualstudio.com/items?itemName=ms-devlabs.custom-terraform-tasks**

Or search for "Terraform" in the Azure DevOps Marketplace.

---

## Step 2: Install Extension

### On the Marketplace Page:

1. **Click the green "Get it free" button**

2. **Select your Azure DevOps organization**
   - Choose from the dropdown
   - Example: `https://dev.azure.com/YOUR_ORG`

3. **Click "Install"**

4. **Wait for confirmation** (~30 seconds)
   - You should see "Successfully installed"

### Screenshot Guide:

```
┌─────────────────────────────────────────────┐
│  Terraform                                  │
│  By Microsoft DevLabs                       │
│                                             │
│  [Get it free]  ← Click this               │
│                                             │
│  Select an Azure DevOps organization        │
│  ┌─────────────────────────┐               │
│  │ YOUR_ORG              ▼ │ ← Select      │
│  └─────────────────────────┘               │
│                                             │
│  [Install]  ← Click this                   │
└─────────────────────────────────────────────┘
```

---

## Step 3: Verify Installation

### Method A: Via Azure DevOps UI

1. Go to your Azure DevOps organization settings
   ```
   https://dev.azure.com/YOUR_ORG/_settings/extensions
   ```

2. Look for "Terraform" in the installed extensions list

3. You should see:
   - **Name:** Terraform
   - **Publisher:** Microsoft DevLabs
   - **Status:** Installed ✅

### Method B: Via Pipeline

1. Go to your failed pipeline
2. Click "Run new"
3. If the extension is installed, the pipeline will start successfully

---

## Step 4: Re-run Pipeline

Once installed:

### Option A: Re-run Failed Pipeline

1. **Go to your failed pipeline run**
   ```
   https://dev.azure.com/YOUR_ORG/YOUR_PROJECT/_build/results?buildId=YOUR_BUILD_ID
   ```

2. **Click "Run new"** (top right)

3. **Select branch:** main

4. **Click "Run"**

### Option B: Trigger New Pipeline Run

```bash
# Make a small change and push
echo "# Extension installed - $(date)" >> terraform/environments/dev/PIPELINE_RUN.md

git add terraform/environments/dev/PIPELINE_RUN.md
git commit -m "chore: trigger pipeline after extension install"
git push origin main
```

---

## Step 5: Monitor Pipeline Success

### Expected Result:

```
✅ Stage: Plan
  ✅ Install Terraform (using TerraformInstaller task)
  ✅ Terraform Init
  ✅ Terraform Validate
  ✅ Terraform Plan
  ✅ Publish Artifact

✅ Stage: Apply (conditional on main branch)
  ✅ Install Terraform
  ✅ Terraform Init
  ✅ Terraform Apply
  ✅ Save Outputs
```

**Total Duration:** ~3-5 minutes

---

## Troubleshooting

### Issue: "You don't have permission to install extensions"

**Solution 1: Request Installation**

Email your Azure DevOps administrator:

```
Subject: Request to Install Terraform Extension

Hi [Admin Name],

Could you please install the Terraform extension for our Azure DevOps organization?

Extension: https://marketplace.visualstudio.com/items?itemName=ms-devlabs.custom-terraform-tasks

This is required for our FinRisk infrastructure pipeline.

Thanks!
```

**Solution 2: Use Script-Based Pipeline**

If you can't get admin approval, use the script-based pipeline instead:

```bash
# Switch pipeline to script version (no extension needed)
# In Azure DevOps, update pipeline to use:
# pipelines/azure-pipelines-infra-script.yml
```

### Issue: Extension installs but pipeline still fails

**Check 1: Extension Enabled**

1. Go to organization settings
2. Navigate to Extensions
3. Verify Terraform is **enabled** (not just installed)

**Check 2: Clear Pipeline Cache**

1. Edit pipeline in Azure DevOps
2. Click "Save" (even without changes)
3. This forces pipeline cache refresh

**Check 3: Agent Has Access**

If using self-hosted agent:
1. Restart the agent service
2. Verify agent can access marketplace extensions

### Issue: Wrong Terraform version

The extension should install version `1.7.0` (specified in pipeline).

To verify:
1. Check pipeline logs for "Installing Terraform..."
2. Look for version number
3. Should match `terraformVersion: '1.7.0'`

---

## Alternative: Pre-install Terraform on Agent

If you have a **self-hosted agent**, you can pre-install Terraform and skip the installer task.

### On Agent Machine:

```bash
# SSH to agent
cd /tmp

# Download Terraform 1.7.0
wget https://releases.hashicorp.com/terraform/1.7.0/terraform_1.7.0_linux_amd64.zip

# Unzip
unzip terraform_1.7.0_linux_amd64.zip

# Move to PATH
sudo mv terraform /usr/local/bin/

# Verify
terraform version
# Output: Terraform v1.7.0
```

### Update Pipeline:

Remove the TerraformInstaller step (lines 50-52):

```yaml
# REMOVE THESE LINES:
- task: TerraformInstaller@1
  inputs:
    terraformVersion: '$(terraformVersion)'
```

Terraform will be available from PATH instead.

---

## What the Extension Provides

### Tasks Included:

1. **TerraformInstaller@1**
   - Installs specified Terraform version
   - Adds to PATH
   - Supports version caching

2. **TerraformTaskV4@4**
   - Runs Terraform commands (init, plan, apply, etc.)
   - Integrates with Azure service connections
   - Manages state backend automatically
   - Better error handling

### Benefits:

- ✅ Official Microsoft extension
- ✅ Maintained and supported
- ✅ Azure-specific integrations
- ✅ State management helpers
- ✅ Service principal auth handling
- ✅ Plan artifact management

---

## Quick Reference

### Extension Details

- **Name:** Terraform
- **Publisher:** Microsoft DevLabs
- **ID:** ms-devlabs.custom-terraform-tasks
- **Version:** Latest (auto-updates)
- **Link:** https://marketplace.visualstudio.com/items?itemName=ms-devlabs.custom-terraform-tasks

### Required Tasks

Your pipeline uses:
- `TerraformInstaller@1` - Line 50
- `TerraformTaskV4@4` - Lines 54, 66, 73, 108, 120

Both are included in the same extension.

---

## Next Steps After Installation

1. ✅ **Install extension** (this guide)
2. ✅ **Re-run pipeline**
3. ✅ **Monitor for success**
4. ✅ **Verify infrastructure**
5. 📊 **Review outputs**

---

## Need Help?

If you encounter issues:

1. **Check extension installation:** Organization Settings → Extensions
2. **Verify permissions:** You need "Manage Extensions" permission
3. **Review pipeline logs:** Look for specific error messages
4. **Try script version:** Use `azure-pipelines-infra-script.yml` as fallback

---

## Ready to Install?

👉 **Click here now:** https://marketplace.visualstudio.com/items?itemName=ms-devlabs.custom-terraform-tasks

Then return here for Step 4 (re-run pipeline).
