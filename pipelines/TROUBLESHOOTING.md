# Pipeline Fix - Missing Terraform Extension

## Issue

```
A task is missing. The pipeline references a task called 'TerraformInstaller'.
This usually indicates the task isn't installed.
```

## Root Cause

The Azure DevOps pipeline uses the **Terraform extension** which is not installed in your organization.

---

## Solution 1: Install Terraform Extension (Recommended - 5 minutes)

### Step 1: Install Extension from Marketplace

1. **Open Azure DevOps Marketplace**
   ```
   https://marketplace.visualstudio.com/items?itemName=ms-devlabs.custom-terraform-tasks
   ```

2. **Click "Get it free"**

3. **Select your Azure DevOps organization**

4. **Click "Install"**

5. **Wait for installation to complete** (~30 seconds)

### Step 2: Re-run the Pipeline

Once installed:

1. Go back to your failed pipeline run
2. Click **"Re-run failed jobs"** or **"Run new"**
3. Pipeline should now succeed

**Advantages:**
- ✅ Uses official Microsoft Terraform tasks
- ✅ Better integration with Azure
- ✅ Automatic Terraform installation
- ✅ State management built-in

---

## Solution 2: Use Script-Based Pipeline (No Extension Required)

If you **cannot install extensions** (permissions issue), use this alternative pipeline.

### Create Alternative Pipeline

This uses bash scripts instead of Terraform tasks - no extension needed.

Save as `pipelines/azure-pipelines-infra-script.yml`:

```yaml
# Azure DevOps Infrastructure Pipeline (Script-Based)
# FinRisk Platform - No Extensions Required
#
# This pipeline uses bash scripts instead of Terraform tasks
# No marketplace extensions required

name: FinRisk-IaC-Terraform-Script-$(Date:yyyyMMdd-HHmm)$(Rev:.r)

trigger:
  branches:
    include:
      - main
  paths:
    include:
      - terraform/**
      - pipelines/azure-pipelines-infra-script.yml

pr:
  branches:
    include:
      - main
  paths:
    include:
      - terraform/**

variables:
  - group: finrisk-dev
  - name: azureSubscription
    value: 'azure-service-connection'
  - name: environmentName
    value: 'dev'
  - name: terraformVersion
    value: '1.7.0'
  - name: terraformWorkingDirectory
    value: '$(System.DefaultWorkingDirectory)/terraform/environments/dev'

stages:
  - stage: Plan
    displayName: 'Terraform Plan'
    jobs:
      - job: TerraformPlan
        pool: Default
        steps:
          - checkout: self
            fetchDepth: 1
            clean: false

          # Install Terraform using bash
          - bash: |
              set -e
              echo "Installing Terraform $(terraformVersion)..."

              # Download Terraform
              wget -q https://releases.hashicorp.com/terraform/$(terraformVersion)/terraform_$(terraformVersion)_linux_amd64.zip

              # Unzip
              unzip -q terraform_$(terraformVersion)_linux_amd64.zip

              # Make executable and move to PATH
              chmod +x terraform
              sudo mv terraform /usr/local/bin/

              # Verify installation
              terraform version
            displayName: 'Install Terraform'

          # Azure Login
          - task: AzureCLI@2
            displayName: 'Terraform Init'
            inputs:
              azureSubscription: '$(azureSubscription)'
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                set -e
                cd $(terraformWorkingDirectory)

                # Initialize Terraform
                terraform init \
                  -backend-config="storage_account_name=$(terraformStateStorageAccount)" \
                  -backend-config="container_name=tfstate" \
                  -backend-config="key=finrisk-$(environmentName).tfstate" \
                  -backend-config="resource_group_name=rg-terraform-state"
              addSpnToEnvironment: true

          - task: AzureCLI@2
            displayName: 'Terraform Validate'
            inputs:
              azureSubscription: '$(azureSubscription)'
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                set -e
                cd $(terraformWorkingDirectory)
                terraform validate
              addSpnToEnvironment: true

          - task: AzureCLI@2
            displayName: 'Terraform Plan'
            inputs:
              azureSubscription: '$(azureSubscription)'
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                set -e
                cd $(terraformWorkingDirectory)
                terraform plan -out=tfplan
              addSpnToEnvironment: true

          - publish: '$(terraformWorkingDirectory)/tfplan'
            artifact: tfplan
            displayName: 'Publish Plan Artifact'

  - stage: Apply
    displayName: 'Terraform Apply'
    dependsOn: Plan
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
    jobs:
      - deployment: TerraformApply
        pool: Default
        environment: '$(environmentName)-infrastructure'
        strategy:
          runOnce:
            deploy:
              steps:
                - checkout: self
                  fetchDepth: 1
                  clean: false

                - download: current
                  artifact: tfplan

                - bash: |
                    set -e
                    echo "Installing Terraform $(terraformVersion)..."
                    wget -q https://releases.hashicorp.com/terraform/$(terraformVersion)/terraform_$(terraformVersion)_linux_amd64.zip
                    unzip -q terraform_$(terraformVersion)_linux_amd64.zip
                    chmod +x terraform
                    sudo mv terraform /usr/local/bin/
                    terraform version
                  displayName: 'Install Terraform'

                - task: AzureCLI@2
                  displayName: 'Terraform Init'
                  inputs:
                    azureSubscription: '$(azureSubscription)'
                    scriptType: 'bash'
                    scriptLocation: 'inlineScript'
                    inlineScript: |
                      set -e
                      cd $(terraformWorkingDirectory)
                      terraform init \
                        -backend-config="storage_account_name=$(terraformStateStorageAccount)" \
                        -backend-config="container_name=tfstate" \
                        -backend-config="key=finrisk-$(environmentName).tfstate" \
                        -backend-config="resource_group_name=rg-terraform-state"
                    addSpnToEnvironment: true

                - task: AzureCLI@2
                  displayName: 'Terraform Apply'
                  inputs:
                    azureSubscription: '$(azureSubscription)'
                    scriptType: 'bash'
                    scriptLocation: 'inlineScript'
                    inlineScript: |
                      set -e
                      cd $(terraformWorkingDirectory)

                      # Copy plan file from artifact
                      cp $(Pipeline.Workspace)/tfplan/tfplan ./tfplan

                      # Apply the plan
                      terraform apply tfplan
                    addSpnToEnvironment: true

                - task: AzureCLI@2
                  displayName: 'Save Outputs'
                  inputs:
                    azureSubscription: '$(azureSubscription)'
                    scriptType: 'bash'
                    scriptLocation: 'inlineScript'
                    inlineScript: |
                      set -e
                      cd $(terraformWorkingDirectory)
                      terraform output -json > terraform-outputs.json
                    addSpnToEnvironment: true

                - publish: '$(terraformWorkingDirectory)/terraform-outputs.json'
                  artifact: terraform-outputs
                  displayName: 'Publish Outputs'
```

**Advantages:**
- ✅ No extension required
- ✅ Works immediately
- ✅ Full control over Terraform version
- ✅ Uses AzureCLI task (built-in)

**Disadvantages:**
- ⚠️ More verbose
- ⚠️ Manual Terraform installation
- ⚠️ Less Azure DevOps integration

---

## Recommendation

### If you have admin permissions:
👉 **Use Solution 1** - Install the extension (5 minutes)

### If you cannot install extensions:
👉 **Use Solution 2** - Script-based pipeline (works immediately)

---

## Quick Fix Commands

### Option A: Install Extension (Admin Required)

1. Visit: https://marketplace.visualstudio.com/items?itemName=ms-devlabs.custom-terraform-tasks
2. Click "Get it free"
3. Install to your organization
4. Re-run pipeline

### Option B: Switch to Script Pipeline

```bash
# Create alternative pipeline file
# (File content is above)

# Update pipeline in Azure DevOps to use new file:
# pipelines/azure-pipelines-infra-script.yml
```

---

## Testing the Fix

After applying either solution:

```bash
# Local validation first
bash pipelines/test-infra-pipeline.sh

# Then trigger pipeline
git add .
git commit -m "fix: update pipeline for Terraform extension"
git push origin main
```

---

## Additional Notes

### If Using Self-Hosted Agent

Your pipeline uses `pool: Default` which suggests a self-hosted agent. Ensure:

1. **Terraform is installed** on the agent machine
   ```bash
   # SSH to agent and install
   wget https://releases.hashicorp.com/terraform/1.7.0/terraform_1.7.0_linux_amd64.zip
   unzip terraform_1.7.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   ```

2. **Or pre-install** and skip installation step in pipeline

3. **Azure CLI is installed** on agent
   ```bash
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
   ```

### Extension Installation Permissions

If you get "Permission denied" when installing extension:

1. Ask your **Azure DevOps organization admin** to install
2. Or request **Project Collection Administrator** role
3. Or use **Solution 2** (script-based) which requires no extensions

---

## Next Steps

1. ✅ Choose Solution 1 or 2 above
2. ✅ Apply the fix
3. ✅ Re-run or trigger new pipeline
4. ✅ Monitor in Azure DevOps
5. ✅ Verify success

