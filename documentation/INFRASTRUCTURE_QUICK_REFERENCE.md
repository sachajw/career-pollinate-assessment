# Infrastructure Quick Reference Guide

Quick reference for common operations on the FinRisk Platform Azure infrastructure.

---

## 🔑 Key Information

| Resource | Name | Value |
|----------|------|-------|
| Resource Group | rg-finrisk-dev | East US 2 |
| Container App | ca-finrisk-dev | https://ca-finrisk-dev--km4fyaz.proudwater-4005d979.eastus2.azurecontainerapps.io |
| Container Registry | acrfinriskdev | acrfinriskdev.azurecr.io |
| Key Vault | kv-finrisk-dev | https://kv-finrisk-dev.vault.azure.net/ |
| App Insights | appi-finrisk-dev | App ID: 945b60c7-fe47-410b-8450-7bf653111e34 |
| Managed Identity | Principal ID | 721990f7-f4d0-4a2e-a7ea-cf5526d42993 |

---

## 🚀 Common Operations

### Deploy Application Updates

```bash
# 1. Build and push Docker image
cd app
az acr login --name acrfinriskdev
docker build -t acrfinriskdev.azurecr.io/applicant-validator:$(git rev-parse --short HEAD) .
docker push acrfinriskdev.azurecr.io/applicant-validator:$(git rev-parse --short HEAD)

# 2. Update Container App with new image
az containerapp update \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --image acrfinriskdev.azurecr.io/applicant-validator:$(git rev-parse --short HEAD)
```

### View Logs

```bash
# Follow live logs
az containerapp logs show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --follow

# View recent logs (last 50 lines)
az containerapp logs show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --tail 50

# View logs in Azure Portal
echo "https://portal.azure.com/#@/resource/subscriptions/94b0c11e-3389-4ca0-b998-a3894e174f3c/resourceGroups/rg-finrisk-dev/providers/Microsoft.App/containerApps/ca-finrisk-dev/logs"
```

### Manage Secrets

```bash
# Add/update secret in Key Vault
az keyvault secret set \
  --vault-name kv-finrisk-dev \
  --name RISKSHIELD-API-KEY \
  --value "your-secret-value"

# List all secrets
az keyvault secret list \
  --vault-name kv-finrisk-dev \
  --query "[].name" -o table

# Get secret value
az keyvault secret show \
  --vault-name kv-finrisk-dev \
  --name RISKSHIELD-API-KEY \
  --query "value" -o tsv

# Delete secret (soft delete)
az keyvault secret delete \
  --vault-name kv-finrisk-dev \
  --name RISKSHIELD-API-KEY
```

### Scale Application

```bash
# Manual scale
az containerapp update \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --min-replicas 1 \
  --max-replicas 10

# Disable scale-to-zero (always keep 1 instance)
az containerapp update \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --min-replicas 1

# Re-enable scale-to-zero
az containerapp update \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --min-replicas 0
```

### Monitor Application

```bash
# Check app status
az containerapp show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query "properties.{status:runningStatus,replicas:replicaCount,url:configuration.ingress.fqdn}" -o table

# View current revision
az containerapp revision list \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query "[].{name:name,active:properties.active,replicas:properties.replicas}" -o table

# View metrics in Application Insights
az monitor app-insights component show \
  --app appi-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query "appId" -o tsv
```

### Access Container Registry

```bash
# Login to ACR
az acr login --name acrfinriskdev

# List repositories
az acr repository list --name acrfinriskdev -o table

# List tags for a repository
az acr repository show-tags \
  --name acrfinriskdev \
  --repository applicant-validator \
  --orderby time_desc -o table

# Delete old images
az acr repository delete \
  --name acrfinriskdev \
  --repository applicant-validator \
  --tag old-tag
```

---

## 🔧 Terraform Operations

### Basic Commands

```bash
# Navigate to environment
cd terraform/environments/dev

# Set backend auth (required for all commands)
export ARM_ACCESS_KEY=$(az storage account keys list --resource-group rg-terraform-state --account-name stfinrisktf4d9e8d --query '[0].value' -o tsv)

# View current infrastructure
terraform show

# View outputs
terraform output

# Refresh state from Azure
terraform refresh

# Format code
terraform fmt -recursive

# Validate configuration
terraform validate
```

### Making Infrastructure Changes

```bash
# 1. Edit .tf files as needed

# 2. Plan changes
terraform plan -out=tfplan

# 3. Review plan carefully

# 4. Apply changes
terraform apply tfplan

# Alternative: Auto-approve (use with caution)
terraform apply -auto-approve
```

### View Specific Resources

```bash
# List all resources
terraform state list

# Show specific resource
terraform state show module.container_app.azurerm_container_app.this

# Show outputs in JSON
terraform output -json

# Get specific output
terraform output container_app_url
```

---

## 🐛 Troubleshooting

### Container App Not Starting

```bash
# 1. Check app status
az containerapp show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query "properties.{status:runningStatus,message:latestRevisionFqdn}"

# 2. View logs for errors
az containerapp logs show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --tail 100

# 3. Check revision status
az containerapp revision list \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query "[].{name:name,active:properties.active,health:properties.healthState}"

# 4. Restart container app
az containerapp revision restart \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --revision <revision-name>
```

### Cannot Pull from Container Registry

```bash
# 1. Verify managed identity has ACR pull permission
az role assignment list \
  --assignee 721990f7-f4d0-4a2e-a7ea-cf5526d42993 \
  --scope /subscriptions/94b0c11e-3389-4ca0-b998-a3894e174f3c/resourceGroups/rg-finrisk-dev/providers/Microsoft.ContainerRegistry/registries/acrfinriskdev

# 2. If missing, add role assignment
az role assignment create \
  --assignee 721990f7-f4d0-4a2e-a7ea-cf5526d42993 \
  --role AcrPull \
  --scope /subscriptions/94b0c11e-3389-4ca0-b998-a3894e174f3c/resourceGroups/rg-finrisk-dev/providers/Microsoft.ContainerRegistry/registries/acrfinriskdev

# 3. Wait 2-3 minutes for propagation, then restart
```

### Cannot Access Key Vault Secrets

```bash
# 1. Verify managed identity has Key Vault permission
az role assignment list \
  --assignee 721990f7-f4d0-4a2e-a7ea-cf5526d42993 \
  --scope /subscriptions/94b0c11e-3389-4ca0-b998-a3894e174f3c/resourceGroups/rg-finrisk-dev/providers/Microsoft.KeyVault/vaults/kv-finrisk-dev

# 2. If missing, add role assignment
az role assignment create \
  --assignee 721990f7-f4d0-4a2e-a7ea-cf5526d42993 \
  --role "Key Vault Secrets User" \
  --scope /subscriptions/94b0c11e-3389-4ca0-b998-a3894e174f3c/resourceGroups/rg-finrisk-dev/providers/Microsoft.KeyVault/vaults/kv-finrisk-dev

# 3. Verify secret exists
az keyvault secret list --vault-name kv-finrisk-dev
```

### Terraform State Lock Issues

```bash
# If terraform apply fails with "state locked" error:

# 1. List locks
az lock list --resource-group rg-finrisk-dev

# 2. If stuck, force unlock (use with extreme caution)
terraform force-unlock <lock-id>

# 3. Alternative: Wait for lock timeout (usually 2-3 minutes)
```

### High Costs Detected

```bash
# 1. Check Log Analytics ingestion
az monitor log-analytics workspace show \
  --resource-group rg-finrisk-dev \
  --workspace-name log-finrisk-dev \
  --query "retentionInDays"

# 2. Reduce Application Insights sampling
az monitor app-insights component update \
  --app appi-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --sampling-percentage 50

# 3. Enable scale-to-zero if disabled
az containerapp update \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --min-replicas 0

# 4. View Azure Cost Management
echo "https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/overview"
```

---

## 🧪 Testing Endpoints

### Health Check

```bash
# Liveness probe
curl https://ca-finrisk-dev--km4fyaz.proudwater-4005d979.eastus2.azurecontainerapps.io/health

# Expected: {"status": "healthy"}
```

### Readiness Check

```bash
# Readiness probe
curl https://ca-finrisk-dev--km4fyaz.proudwater-4005d979.eastus2.azurecontainerapps.io/ready

# Expected: {"status": "ready"}
```

### API Validation Endpoint

```bash
# Test applicant validation
curl -X POST https://ca-finrisk-dev--km4fyaz.proudwater-4005d979.eastus2.azurecontainerapps.io/validate \
  -H "Content-Type: application/json" \
  -d '{
    "firstName": "Jane",
    "lastName": "Doe",
    "idNumber": "9001011234088"
  }'

# Expected: {"riskScore": 72, "riskLevel": "MEDIUM", "correlationId": "..."}
```

---

## 📊 Monitoring Queries

### Log Analytics (KQL Queries)

Access Log Analytics in Azure Portal and run these queries:

```kql
// Container App Logs - Last hour
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(1h)
| where ContainerAppName_s == "ca-finrisk-dev"
| order by TimeGenerated desc
| project TimeGenerated, Log_s, ContainerName_s

// Error Logs
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(24h)
| where Log_s contains "error" or Log_s contains "ERROR"
| project TimeGenerated, Log_s

// Request Count by Status Code
AppRequests
| where TimeGenerated > ago(1h)
| summarize Count=count() by ResultCode
| render barchart

// Average Response Time
AppRequests
| where TimeGenerated > ago(1h)
| summarize AvgDuration=avg(DurationMs) by bin(TimeGenerated, 5m)
| render timechart
```

---

## 🔐 Security Checklist

### Daily
- [ ] Review application logs for errors
- [ ] Check Application Insights for anomalies

### Weekly
- [ ] Review Key Vault access logs
- [ ] Check for failed authentication attempts
- [ ] Verify backup/disaster recovery procedures

### Monthly
- [ ] Rotate Key Vault secrets
- [ ] Review RBAC assignments
- [ ] Audit container images for vulnerabilities
- [ ] Review and optimize costs

---

## 📞 Support Contacts

| Issue Type | Contact | Notes |
|------------|---------|-------|
| Infrastructure | Platform Team | Terraform issues, Azure resources |
| Application | Development Team | API bugs, performance |
| Security | Security Team | Vulnerabilities, compliance |
| Costs | Finance Team | Budget overruns |

---

## 🔗 Quick Links

- [Azure Portal - Resource Group](https://portal.azure.com/#@/resource/subscriptions/94b0c11e-3389-4ca0-b998-a3894e174f3c/resourceGroups/rg-finrisk-dev)
- [Container App Metrics](https://portal.azure.com/#@/resource/subscriptions/94b0c11e-3389-4ca0-b998-a3894e174f3c/resourceGroups/rg-finrisk-dev/providers/Microsoft.App/containerApps/ca-finrisk-dev/metrics)
- [Application Insights](https://portal.azure.com/#@/resource/subscriptions/94b0c11e-3389-4ca0-b998-a3894e174f3c/resourceGroups/rg-finrisk-dev/providers/Microsoft.Insights/components/appi-finrisk-dev)
- [Log Analytics](https://portal.azure.com/#@/resource/subscriptions/94b0c11e-3389-4ca0-b998-a3894e174f3c/resourceGroups/rg-finrisk-dev/providers/Microsoft.OperationalInsights/workspaces/log-finrisk-dev/logs)
- [Key Vault](https://portal.azure.com/#@/resource/subscriptions/94b0c11e-3389-4ca0-b998-a3894e174f3c/resourceGroups/rg-finrisk-dev/providers/Microsoft.KeyVault/vaults/kv-finrisk-dev)
- [Container Registry](https://portal.azure.com/#@/resource/subscriptions/94b0c11e-3389-4ca0-b998-a3894e174f3c/resourceGroups/rg-finrisk-dev/providers/Microsoft.ContainerRegistry/registries/acrfinriskdev)

---

**Last Updated:** February 15, 2026
