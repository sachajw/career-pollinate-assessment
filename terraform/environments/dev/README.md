# Development Environment

This directory contains the Terraform configuration for the **FinRisk Platform Development Environment**.

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
   # Run once to create storage account for Terraform state
   ./scripts/bootstrap-terraform-state.sh eastus2
   ```

## Quick Start

```bash
# 1. Copy example files
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars

# 2. Edit backend.hcl with your storage account details
# 3. Edit terraform.tfvars with your configuration (defaults are fine for dev)

# 4. Initialize Terraform
terraform init -backend-config=backend.hcl

# 5. Plan changes
terraform plan -out=tfplan

# 6. Apply changes
terraform apply tfplan
```

## Development-Specific Settings

| Setting | Value | Reason |
|---------|-------|--------|
| min_replicas | 0 | Scale-to-zero saves costs when idle |
| max_replicas | 5 | Sufficient for development |
| log_retention_days | 30 | Shorter retention saves costs |
| zone_redundancy | false | Not needed for dev |
| acr_sku | Basic | Cheapest option for dev |
| ip_masking | false | Easier debugging |

## Cost Optimization

Development environment estimated monthly cost:

| Resource | SKU | Est. Cost/month |
|----------|-----|-----------------|
| Container App | 0-5 replicas | $0-30 |
| Container Registry | Basic | $5 |
| Key Vault | Standard | $0-3 |
| Log Analytics | 30 days | $5-10 |
| Application Insights | 1GB cap | $2-5 |
| **Total** | | **$12-53** |

With scale-to-zero enabled, costs can be as low as $12/month when idle.

## Common Operations

### View Application Logs

```bash
az containerapp logs show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --follow
```

### Scale Up Temporarily

```bash
# Edit terraform.tfvars
min_replicas = 1

# Apply
terraform apply
```

### Destroy Infrastructure

```bash
# WARNING: This deletes all resources
terraform destroy
```

## Related Documentation

- [ADR-006: Terraform Module Architecture](../../../documentation/adr/006-terraform-module-architecture.md)
- [Main Terraform README](../../README.md)
