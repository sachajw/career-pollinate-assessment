# FinRisk Platform - Azure Infrastructure Deployment Log

**Date:** February 15, 2026
**Environment:** Development (dev)
**Deployed By:** Azure CLI User (azure@pangarabbit.com)
**Terraform Version:** 1.5+
**Azure Provider Version:** 3.117.1

---

## Executive Summary

Successfully deployed the complete Azure infrastructure for the FinRisk Platform (Pollinate Assessment) using Terraform. The deployment includes all core services: Container Apps, Container Registry, Key Vault, and observability stack (Log Analytics + Application Insights).

**Deployment Status:** ✅ Complete
**Resources Created:** 12 Azure resources
**Deployment Duration:** ~15 minutes (excluding troubleshooting)
**Region:** East US 2

---

## Pre-Deployment Setup

### 1. Azure Authentication
- **Status:** Already authenticated via `az login`
- **Subscription:** Azure subscription 1 (94b0c11e-3389-4ca0-b998-a3894e174f3c)
- **Tenant:** Default Directory (azurepangarabbit.onmicrosoft.com)
- **User:** azure@pangarabbit.com

### 2. Terraform Backend Storage Creation

Created dedicated Azure Storage Account for Terraform state management:

```bash
# Resource Group
az group create \
  --name rg-terraform-state \
  --location eastus2 \
  --tags Purpose="Terraform State" Project="finrisk"

# Storage Account (globally unique name)
az storage account create \
  --name stfinrisktf4d9e8d \
  --resource-group rg-terraform-state \
  --location eastus2 \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false

# Container for state files
az storage container create \
  --name tfstate \
  --account-name stfinrisktf4d9e8d \
  --auth-mode login
```

**Storage Account Details:**
- Name: `stfinrisktf4d9e8d`
- SKU: Standard_LRS
- Encryption: Microsoft-managed keys
- TLS: 1.2 minimum
- Public blob access: Disabled

### 3. RBAC Configuration

Granted Storage Blob Data Contributor role to current user:

```bash
az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee <user-object-id> \
  --scope <storage-account-id>
```

**Note:** Initially attempted to use Azure AD authentication (`use_azuread_auth = true`), but encountered permission propagation delays. Switched to access key authentication for immediate deployment success.

### 4. Terraform Configuration Files

Created two essential configuration files:

**backend.hcl** (Terraform state backend):
```hcl
storage_account_name = "stfinrisktf4d9e8d"
container_name       = "tfstate"
key                  = "finrisk-dev.tfstate"
resource_group_name  = "rg-terraform-state"
```

**terraform.tfvars** (Environment variables):
```hcl
location                      = "eastus2"
project_name                  = "finrisk"
environment                   = "dev"
container_app_min_replicas    = 0
container_app_max_replicas    = 5
log_analytics_retention_days  = 30
enable_availability_test      = false
```

---

## Deployment Process

### Phase 1: Terraform Initialization

```bash
cd terraform/environments/dev
terraform init -reconfigure -backend-config=backend.hcl
```

**Result:** ✅ Success
- Backend configured: azurerm (Azure Storage)
- Provider initialized: hashicorp/azurerm v3.117.1
- Modules initialized: 5 modules

### Phase 2: Resource Provider Registration

**Issue Encountered:** Microsoft.App resource provider not registered

```
Error: MissingSubscriptionRegistration: The subscription is not registered
to use namespace 'Microsoft.App'
```

**Resolution:**
```bash
az provider register --namespace Microsoft.App

# Wait for registration to complete
az provider show -n Microsoft.App --query registrationState
```

**Registration Status:** ✅ Completed in ~30 seconds

### Phase 3: Container Registry Authentication Challenge

**Issue Encountered:** Circular dependency with Container App managed identity

The Container App requires:
1. A container image to deploy
2. Registry authentication configured
3. Managed identity created for ACR pull

But the managed identity doesn't exist until the Container App is created.

**Resolution Strategy:**
1. Temporarily use public Microsoft sample image (`mcr.microsoft.com/k8se/quickstart:latest`)
2. Deploy infrastructure to create managed identity
3. Configure ACR pull permissions with the created identity
4. Post-deployment: Update to use private ACR image

**Code Changes:**
- Set `container_image = "mcr.microsoft.com/k8se/quickstart:latest"`
- Set `registry_server = null` (disable ACR auth for initial deployment)
- Keep `enable_acr_pull = true` to create role assignment

### Phase 4: Infrastructure Deployment

```bash
export ARM_ACCESS_KEY="<storage-account-key>"
terraform plan -out=tfplan
terraform apply tfplan
```

**Deployment Order:**
1. Resource Group: `rg-finrisk-dev` (17s)
2. Parallel creation:
   - Container Registry: `acrfinriskdev` (27s)
   - Key Vault: `kv-finrisk-dev` (2m53s)
   - Log Analytics Workspace: `log-finrisk-dev` (51s)
3. Application Insights: `appi-finrisk-dev` (13s)
4. Diagnostic Settings for ACR and Key Vault (4-5s each)
5. Key Vault RBAC: Administrator role for deployer (32s)
6. Container App Environment: `cae-finrisk-dev` (44s)
7. Container App: `ca-finrisk-dev` (25s)
8. RBAC assignments:
   - ACR Pull role (28s)
   - Key Vault Secrets User role (29s)

**Total Deployment Time:** ~4 minutes 30 seconds

---

## Deployed Resources Summary

### Resource Group
- **Name:** rg-finrisk-dev
- **Location:** East US 2
- **Resource ID:** `/subscriptions/94b0c11e-3389-4ca0-b998-a3894e174f3c/resourceGroups/rg-finrisk-dev`

### Observability Stack

#### Log Analytics Workspace
- **Name:** log-finrisk-dev
- **SKU:** PerGB2018
- **Retention:** 30 days
- **Daily Quota:** 5 GB
- **Internet Ingestion:** Enabled
- **Resource ID:** `/subscriptions/.../workspaces/log-finrisk-dev`

#### Application Insights
- **Name:** appi-finrisk-dev
- **Type:** Web
- **Retention:** 90 days
- **Daily Cap:** 2 GB
- **Sampling:** 100%
- **IP Masking:** Disabled (dev environment)
- **App ID:** 945b60c7-fe47-410b-8450-7bf653111e34
- **Connection String:** <sensitive>

### Container Registry
- **Name:** acrfinriskdev
- **Login Server:** acrfinriskdev.azurecr.io
- **SKU:** Basic
- **Admin Access:** Disabled (using managed identity)
- **Public Access:** Enabled
- **Diagnostics:** Enabled (ACR login/repository events)

### Key Vault
- **Name:** kv-finrisk-dev
- **URI:** https://kv-finrisk-dev.vault.azure.net/
- **SKU:** Standard
- **RBAC Authorization:** Enabled
- **Soft Delete:** 90 days
- **Purge Protection:** Enabled
- **Public Access:** Enabled
- **Diagnostics:** Enabled (audit events)
- **Current Secrets:** 0 (to be added)

### Container App Environment
- **Name:** cae-finrisk-dev
- **Zone Redundancy:** Disabled
- **Network:** Azure-managed (no VNet integration)
- **Default Domain:** proudwater-4005d979.eastus2.azurecontainerapps.io
- **Log Analytics:** Integrated with log-finrisk-dev

### Container App
- **Name:** ca-finrisk-dev
- **FQDN:** ca-finrisk-dev--km4fyaz.proudwater-4005d979.eastus2.azurecontainerapps.io
- **URL:** https://ca-finrisk-dev--km4fyaz.proudwater-4005d979.eastus2.azurecontainerapps.io
- **Revision Mode:** Single
- **Current Image:** mcr.microsoft.com/k8se/quickstart:latest (temporary)
- **Target Image:** acrfinriskdev.azurecr.io/applicant-validator:latest (post-deployment)

**Container Configuration:**
- Name: applicant-validator
- CPU: 0.5 vCPU
- Memory: 1 Gi
- Port: 8080

**Scaling:**
- Min Replicas: 0 (scale-to-zero enabled)
- Max Replicas: 5
- Scale Rule: HTTP (100 concurrent requests)

**Health Probes:**
- Liveness: `/health` (30s interval)
- Readiness: `/ready` (10s interval)

**Ingress:**
- External: Enabled (public internet)
- Transport: HTTP
- HTTPS: Required (no insecure connections)
- Traffic: 100% to latest revision

**Environment Variables:**
```
ENVIRONMENT=dev
LOG_LEVEL=INFO
PORT=8080
KEY_VAULT_URL=https://kv-finrisk-dev.vault.azure.net/
APPLICATIONINSIGHTS_CONNECTION_STRING=<sensitive>
```

**Managed Identity:**
- Type: System-assigned
- Principal ID: 721990f7-f4d0-4a2e-a7ea-cf5526d42993
- Tenant ID: 4490c2aa-e417-4ec0-a0c1-c8cb9cc6e311

**RBAC Assignments:**
1. AcrPull on acrfinriskdev
2. Key Vault Secrets User on kv-finrisk-dev

---

## Issues Encountered and Resolutions

### Issue 1: RBAC Propagation Delay
**Problem:** Azure RBAC role assignment for Storage Blob Data Contributor took time to propagate, causing 403 errors.

**Error Message:**
```
Error: Failed to get existing workspaces: StatusCode=403
Code="AuthorizationPermissionMismatch"
```

**Resolution:**
- Waited 30 seconds for propagation
- When still failing, switched to access key authentication
- For production: Use Azure AD auth and allow adequate propagation time (2-5 minutes)

### Issue 2: Microsoft.App Provider Not Registered
**Problem:** Azure subscription not registered for Container Apps resource provider.

**Error Message:**
```
Error: MissingSubscriptionRegistration: The subscription is not registered
to use namespace 'Microsoft.App'
```

**Resolution:**
```bash
az provider register --namespace Microsoft.App
# Wait ~30 seconds for registration
```

**Prevention:** Pre-register all required providers before deployment.

### Issue 3: Container Registry Authentication Circular Dependency
**Problem:** Container App needs managed identity to pull from ACR, but identity doesn't exist until Container App is created.

**Attempted Solutions:**
1. ❌ Self-referencing identity in registry block (Terraform validation error)
2. ❌ Using "system" string as identity reference (API validation error)
3. ✅ Deploy with public image first, then update to ACR image

**Final Resolution:**
- Initial deployment: Public Microsoft sample image
- Post-deployment: Update to private ACR image with managed identity auth
- This is a known pattern for bootstrapping Container Apps with private registries

### Issue 4: Module Configuration for Registry Auth
**Problem:** Container App registry block validation requiring either identity or username/password.

**Resolution:**
- For initial deployment: Removed registry block entirely (using public image)
- For production deployment: Add registry block with managed identity after app exists
- Documented in code comments for future reference

---

## Security Posture

### Identity and Access Management
- ✅ System-assigned managed identities (no credentials)
- ✅ RBAC-based access control (Key Vault, ACR)
- ✅ Principle of least privilege (scoped role assignments)
- ✅ Key Vault Administrator role only for deployer
- ✅ ACR admin access disabled

### Network Security
- ⚠️ Public access enabled (acceptable for dev, not for production)
- ✅ HTTPS enforced on Container App ingress
- ✅ TLS 1.2 minimum on storage accounts
- ⚠️ No VNet integration (future enhancement)
- ⚠️ No private endpoints (future enhancement)

### Data Protection
- ✅ Key Vault soft delete enabled (90 days)
- ✅ Key Vault purge protection enabled
- ✅ Storage account encryption (Microsoft-managed keys)
- ✅ Secrets stored in Key Vault (not environment variables)
- ✅ Application Insights connection string in secure env var

### Compliance and Auditing
- ✅ Diagnostic logs enabled (Key Vault, ACR)
- ✅ All resources tagged for compliance tracking
- ✅ Log Analytics retention configured
- ✅ Application Insights telemetry enabled
- ✅ SOC2 compliance tags applied

---

## Cost Analysis (Development Environment)

### Monthly Estimated Costs (USD)

**Compute:**
- Container App: ~$0.00 - $15.00 (scale-to-zero, usage-based)
- Container App Environment: ~$0.00 (included)

**Storage:**
- Container Registry (Basic): ~$5.00/month
- Log Analytics (5GB quota): ~$0.00 - $25.00 (per GB ingestion)
- Storage Account (state): ~$0.50/month

**Security:**
- Key Vault (Standard): ~$0.03/10K operations
- Application Insights: ~$0.00 - $20.00 (2GB daily cap)

**Total Estimated Monthly Cost:** $5.53 - $65.53

**Cost Optimization Features:**
- ✅ Scale-to-zero enabled (no cost when idle)
- ✅ Basic SKU for Container Registry (not Standard/Premium)
- ✅ Standard SKU for Key Vault (not Premium)
- ✅ Daily quotas on Log Analytics and Application Insights
- ✅ 30-day log retention (not 90+ days)

---

## Terraform Outputs

```hcl
app_insights_app_id                 = "945b60c7-fe47-410b-8450-7bf653111e34"
app_insights_connection_string      = <sensitive>
app_insights_instrumentation_key    = <sensitive>
container_app_fqdn                  = "ca-finrisk-dev--km4fyaz.proudwater-4005d979.eastus2.azurecontainerapps.io"
container_app_identity_principal_id = "721990f7-f4d0-4a2e-a7ea-cf5526d42993"
container_app_url                   = "https://ca-finrisk-dev--km4fyaz.proudwater-4005d979.eastus2.azurecontainerapps.io"
container_registry_login_server     = "acrfinriskdev.azurecr.io"
container_registry_name             = "acrfinriskdev"
key_vault_name                      = "kv-finrisk-dev"
key_vault_uri                       = "https://kv-finrisk-dev.vault.azure.net/"
log_analytics_workspace_id          = "/subscriptions/.../workspaces/log-finrisk-dev"
resource_group_id                   = "/subscriptions/.../resourceGroups/rg-finrisk-dev"
resource_group_name                 = "rg-finrisk-dev"
```

---

## Post-Deployment Tasks

### Immediate (Required)

1. **Add RiskShield API Key to Key Vault**
   ```bash
   az keyvault secret set \
     --vault-name kv-finrisk-dev \
     --name RISKSHIELD-API-KEY \
     --value "your-actual-api-key"
   ```

2. **Build and Push Application Image**
   ```bash
   cd app
   az acr login --name acrfinriskdev
   docker build -t acrfinriskdev.azurecr.io/applicant-validator:latest .
   docker push acrfinriskdev.azurecr.io/applicant-validator:latest
   ```

3. **Update Container App to Use ACR Image**
   - Edit `terraform/environments/dev/main.tf`:
     ```hcl
     container_image = "${module.container_registry.login_server}/applicant-validator:latest"
     registry_server = module.container_registry.login_server
     ```
   - Apply changes:
     ```bash
     terraform apply
     ```

### Short-term (Recommended)

4. **Configure CI/CD Pipeline**
   - Set up Azure DevOps pipeline (pipelines/azure-pipelines.yml)
   - Configure service connections
   - Add pipeline variables

5. **Set Up Monitoring Alerts**
   - Application Insights availability tests
   - Log Analytics alert rules
   - Container App health alerts

6. **Implement Application**
   - FastAPI endpoints (/validate, /health, /ready)
   - RiskShield API integration
   - Unit and integration tests

### Long-term (Future Enhancements)

7. **Production Environment**
   - Create separate terraform/environments/prod
   - Enable zone redundancy
   - Configure private endpoints
   - Implement VNet integration

8. **Security Hardening**
   - Enable Azure AD authentication on Container App
   - Implement API Management
   - Configure WAF rules
   - Enable Azure Defender

---

## Testing and Validation

### Infrastructure Validation

```bash
# Check Container App status
az containerapp show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query "properties.runningStatus"

# Test public endpoint (currently shows sample app)
curl https://ca-finrisk-dev--km4fyaz.proudwater-4005d979.eastus2.azurecontainerapps.io

# View logs
az containerapp logs show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --follow

# Check managed identity
az containerapp identity show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev

# Verify ACR access
az acr login --name acrfinriskdev
docker pull acrfinriskdev.azurecr.io/hello-world:latest

# Test Key Vault access (after adding secrets)
az keyvault secret list --vault-name kv-finrisk-dev
```

### Expected Results
- ✅ Container App running status: "Running"
- ✅ Public endpoint returns HTTP 200
- ✅ Managed identity created with correct RBAC
- ✅ ACR login successful
- ✅ Key Vault accessible

---

## Rollback Procedure

If deployment needs to be rolled back:

```bash
# Destroy all infrastructure
cd terraform/environments/dev
export ARM_ACCESS_KEY="<key>"
terraform destroy -auto-approve

# Remove backend storage (optional)
az group delete --name rg-terraform-state --yes --no-wait
```

**Warning:** This will delete all resources and data. Ensure backups are taken before rollback.

---

## Known Limitations and Future Work

### Current Limitations
1. ⚠️ Container App running sample image (not production application)
2. ⚠️ No CI/CD pipeline configured
3. ⚠️ No custom domain configured
4. ⚠️ No API Management layer
5. ⚠️ No VNet integration
6. ⚠️ Public access enabled (not suitable for production)

### Planned Enhancements
1. Implement production-grade FastAPI application
2. Configure Azure DevOps CI/CD pipeline
3. Set up custom domain with SSL
4. Integrate Azure API Management
5. Implement VNet with private endpoints
6. Add Azure Front Door for CDN/WAF
7. Configure geo-redundancy for production
8. Implement disaster recovery strategy

---

## References

- [Azure Container Apps Documentation](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Terraform AzureRM Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure Key Vault Best Practices](https://learn.microsoft.com/en-us/azure/key-vault/general/best-practices)
- [Project Architecture Documentation](./architecture/solution-architecture.md)
- [Architecture Decision Records](./architecture/adr/)

---

## Appendix: Deployment Commands Reference

### Complete Deployment Sequence

```bash
# 1. Create backend storage
az group create --name rg-terraform-state --location eastus2
az storage account create --name stfinrisktf4d9e8d --resource-group rg-terraform-state --sku Standard_LRS
az storage container create --name tfstate --account-name stfinrisktf4d9e8d --auth-mode login

# 2. Grant permissions
az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee $(az ad signed-in-user show --query id -o tsv) \
  --scope $(az storage account show --name stfinrisktf4d9e8d --resource-group rg-terraform-state --query id -o tsv)

# 3. Register resource provider
az provider register --namespace Microsoft.App

# 4. Initialize Terraform
cd terraform/environments/dev
export ARM_ACCESS_KEY=$(az storage account keys list --resource-group rg-terraform-state --account-name stfinrisktf4d9e8d --query '[0].value' -o tsv)
terraform init -backend-config=backend.hcl

# 5. Deploy infrastructure
terraform plan -out=tfplan
terraform apply tfplan
```

### Terraform State Management

```bash
# View current state
terraform show

# List all resources
terraform state list

# View specific resource
terraform state show module.container_app.azurerm_container_app.this

# Refresh state from Azure
terraform refresh

# View outputs
terraform output
terraform output -json
```

---

**Document Version:** 1.0
**Last Updated:** February 15, 2026
**Next Review Date:** March 15, 2026
