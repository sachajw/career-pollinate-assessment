# Production Environment

This directory contains the Terraform configuration for the **FinRisk Platform Production Environment**.

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
- [Operations Runbook](../../../documentation/runbooks/OPERATIONS_RUNBOOK.md)
- [Infrastructure Quick Reference](../../../documentation/INFRASTRUCTURE_QUICK_REFERENCE.md)
