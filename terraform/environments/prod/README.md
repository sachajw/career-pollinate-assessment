# Production Environment

This directory contains the Terraform configuration for the **FinRisk Platform Production Environment**.

## Assessment Note

For this technical assessment, only the **dev environment** is deployed due to Azure subscription quota limits:
- **Container App Environments**: Limited to 1 per subscription
- **Current deployment**: `rg-finrisk-dev` in `eastus2`

In a production scenario, this configuration would deploy to a separate subscription or with increased quotas.

## Prerequisites

Before deploying, ensure you have:

1. **Azure CLI installed and authenticated**
   ```bash
   brew install azure-cli     # macOS
   az login                    # Authenticate
   az account show             # Verify subscription
   ```

2. **Terraform installed (>= 1.5.0)**
   ```bash
   brew install terraform
   terraform version
   ```

3. **Terraform state storage bootstrapped**
   ```bash
   ./scripts/bootstrap-terraform-state.sh <region>
   ```

4. **Azure quota verification**
   ```bash
   # Check Container App Environment quota
   az quota show --scope /subscriptions/<sub-id> --resource-name ContainerAppsManagedEnvironments --namespace Microsoft.App
   ```

## Quick Start

```bash
# 1. Copy example files
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars

# 2. Edit backend.hcl with your storage account details
# 3. Edit terraform.tfvars with your configuration

# 4. Initialize Terraform
terraform init -backend-config=backend.hcl

# 5. Plan changes
terraform plan -out=tfplan

# 6. Apply changes (requires approval)
terraform apply tfplan
```

## Production-Specific Settings

| Setting | Dev | Prod | Reason |
|---------|-----|------|--------|
| min_replicas | 0 | 2 | High availability, no cold starts |
| max_replicas | 5 | 10 | Higher capacity |
| log_retention_days | 30 | 90 | Compliance requirements |
| zone_redundancy | false | true | HA across availability zones |
| acr_sku | Basic | Standard | Better performance |
| ip_masking | false | true | Privacy/compliance |
| availability_test | false | true | Proactive monitoring |

## Custom Domain

- **Domain**: `finrisk.pangarabbit.com`
- **Certificate**: `finrisk-pangarabbit-cert` (wildcard)

## CI/CD Integration

The production environment is deployed via the `main` branch:

```
dev branch  → dev environment  (rg-finrisk-dev)
main branch → prod environment (rg-finrisk-prod)
```

### Azure DevOps Setup Required

1. **Variable Group**: `finrisk-prod`
   - `terraformStateStorageAccount` - storage account for state

2. **Environments** (with approvals):
   - `prod-infrastructure` - for terraform apply
   - `prod` - for container app deployment

3. **Service Connections**:
   - `acr-prod-service-connection` - for prod container registry

## Security Considerations

1. **Managed Identity**: All Azure service authentication uses Managed Identity
2. **Key Vault**: Secrets stored in Azure Key Vault with RBAC access
3. **HTTPS Only**: Ingress configured for HTTPS only
4. **IP Masking**: Application Insights masks client IPs for privacy

## Cost Optimization

Production environment estimated monthly cost:

| Resource | SKU | Est. Cost/month |
|----------|-----|-----------------|
| Container App | 2-10 replicas | $50-150 |
| Container Registry | Standard | $5 |
| Key Vault | Standard | $0-5 |
| Log Analytics | 90 days | $10-30 |
| Application Insights | 5GB cap | $10-20 |
| **Total** | | **$75-210** |

## Disaster Recovery

- **Soft Delete**: Key Vault and storage have 90-day soft delete
- **Purge Protection**: Enabled to prevent accidental deletion
- **Zone Redundancy**: Container App deployed across availability zones

## Related Documentation

- [ADR-006: Terraform Module Architecture](../../../documentation/adr/006-terraform-module-architecture.md)
- [Main Terraform README](../../README.md)
