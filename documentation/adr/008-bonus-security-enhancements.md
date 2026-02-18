# ADR-008: Bonus Security Enhancements

**Status:** Accepted
**Date:** 2026-02-18
**Decision Makers:** Security Architecture Team
**Technical Story:** Pollinate Platform Engineering Assessment - Bonus Security Items

## Context

The technical assessment (§4 Security Requirements) lists three optional bonus security items beyond the mandatory requirements:

1. **Network Restrictions** — IP allowlisting on Container App ingress and Key Vault network ACLs
2. **Azure AD Authentication** — Protect `/api/v1/validate` endpoint with Azure AD OAuth2 tokens
3. **Private Endpoints** — Remove public network access from Key Vault and ACR; route traffic over VNet

These are optional enhancements that strengthen the security posture but add complexity and cost.

## Decision

We will implement all three bonus security items as **opt-in features** controlled by Terraform variables, allowing teams to enable them based on environment requirements.

---

## Item 1: Network Restrictions

### Decision: IP Security Restrictions + Key Vault Network ACLs

| Criterion | Weight | IP Restrictions | No Restrictions |
|-----------|--------|-----------------|-----------------|
| Security | Critical | ⭐⭐⭐⭐⭐ | ⭐⭐ |
| Simplicity | High | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Flexibility | Medium | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |

### Implementation

**Container App IP Security Restrictions:**

```hcl
# In terraform/environments/dev/main.tf
ip_security_restrictions = [
  {
    name             = "allow-all"
    ip_address_range = "0.0.0.0/0"
    action           = "Allow"
    description      = "Allow all — replace with specific IPs in production"
  }
]
```

**Key Vault Network ACLs:**

```hcl
# In terraform/environments/dev/main.tf
network_acls_enabled        = true
network_acls_bypass         = "AzureServices"  # Container App MI can still access
network_acls_default_action = "Deny"
allowed_ip_ranges           = var.kv_allowed_ips  # Pipeline agent IPs
```

### New Variable

```hcl
variable "kv_allowed_ips" {
  description = "IP ranges (CIDR) allowed to access Key Vault directly"
  type        = list(string)
  default     = []
}
```

### Verification

```bash
# Test Key Vault ACL — should fail without whitelisted IP
az keyvault secret list --vault-name kv-finrisk-dev
# Expected: Forbidden (403) if IP not in allowed list

# Container App should still work (AzureServices bypass)
curl https://ca-finrisk-dev.eastus2.azurecontainerapps.io/health
# Expected: 200 OK
```

---

## Item 2: Azure AD Authentication (EasyAuth)

### Decision: Container Apps Built-in Authentication via azapi Provider

The `azurerm_container_app_auth_configs` resource is only available in AzureRM 4.x. We use the `azapi` provider (Microsoft's official REST API shim) to configure EasyAuth with AzureRM 3.x.

| Criterion | Weight | EasyAuth | Custom Auth |
|-----------|--------|----------|-------------|
| Security | Critical | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| Code Changes | High | ⭐⭐⭐⭐⭐ (none) | ⭐⭐ (middleware) |
| Provider Dependency | Medium | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |

### Implementation

**azapi Resource for Auth Config:**

```hcl
# In terraform/modules/container-app/main.tf
data "azurerm_client_config" "current" {}

resource "azapi_resource" "auth_configs" {
  count = var.aad_client_id != null ? 1 : 0

  type      = "Microsoft.App/containerApps/authConfigs@2023-05-01"
  name      = "current"
  parent_id = azurerm_container_app.this.id

  body = jsonencode({
    properties = {
      platform = { enabled = true }
      globalValidation = {
        unauthenticatedClientAction = "Return401"
        excludedPaths               = ["/health", "/ready"]
      }
      identityProviders = {
        azureActiveDirectory = {
          registration = {
            openIdIssuer = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/v2.0"
            clientId     = var.aad_client_id
          }
          validation = {
            allowedAudiences = [var.aad_client_id, "api://${var.aad_client_id}"]
          }
        }
      }
    }
  })
}
```

### New Variable

```hcl
variable "aad_client_id" {
  description = "Azure AD App Registration client ID. Set to enable EasyAuth."
  type        = string
  default     = null
}
```

### Prerequisites

1. Create Azure AD App Registration:
   ```bash
   az ad app create --display-name "finrisk-applicant-validator-dev"
   ```

2. Set Application ID URI:
   ```bash
   APP_ID="<client-id>"
   az ad app update --id $APP_ID --identifier-uris "api://$APP_ID"
   ```

### Verification

```bash
# Without token — should return 401
curl https://ca-finrisk-dev.eastus2.azurecontainerapps.io/api/v1/validate
# Expected: 401 Unauthorized

# Health check — should work (excluded from auth)
curl https://ca-finrisk-dev.eastus2.azurecontainerapps.io/health
# Expected: 200 OK

# With token — should work
TOKEN=$(az account get-access-token --resource "api://<client-id>" --query accessToken -o tsv)
curl -H "Authorization: Bearer $TOKEN" https://ca-finrisk-dev.eastus2.azurecontainerapps.io/api/v1/validate
# Expected: 200 OK (or 422 for validation error)
```

---

## Item 3: Private Endpoints

### Decision: VNet + Private Endpoints for Key Vault and ACR

| Criterion | Weight | Private Endpoints | Public Access |
|-----------|--------|-------------------|---------------|
| Security | Critical | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| Cost | High | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Complexity | Medium | ⭐⭐ | ⭐⭐⭐⭐⭐ |

### New Modules

1. **`terraform/modules/networking/`** — VNet + subnets
2. **`terraform/modules/private-endpoints/`** — Private endpoints + DNS zones

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         VNet: 10.0.0.0/16                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────────────┐        ┌─────────────────────────────────┐ │
│  │ snet-private-endpoints │      │ snet-container-app (/23)        │ │
│  │ 10.0.1.0/24             │      │ 10.0.2.0/23                     │ │
│  │                         │      │                                 │ │
│  │  ┌─────────────────┐   │      │  ┌───────────────────────────┐  │ │
│  │  │ PE: Key Vault   │   │      │  │ Container App Environment │  │ │
│  │  │ 10.0.1.4        │◀──┼──────┼──│  (VNet injected)          │  │ │
│  │  └─────────────────┘   │      │  └───────────────────────────┘  │ │
│  │  ┌─────────────────┐   │      │                                 │ │
│  │  │ PE: ACR         │   │      └─────────────────────────────────┘ │
│  │  │ 10.0.1.5        │◀──┼─────────────────────────────────────────┼─┐
│  │  └─────────────────┘   │                                         │ │
│  └─────────────────────┘                                            │ │
│                                                                      │ │
│  ┌─────────────────────────────────────────────────────────────────┐ │ │
│  │ Private DNS Zones                                                │ │ │
│  │ • privatelink.vaultcore.azure.net → Key Vault PE                │ │ │
│  │ • privatelink.azurecr.io        → ACR PE                        │◀┘ │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### New Variable

```hcl
variable "enable_private_endpoints" {
  description = "Enable private endpoints for Key Vault and ACR"
  type        = bool
  default     = false
}
```

### Cost Impact

| Resource | Without PE | With PE | Delta |
|----------|------------|---------|-------|
| ACR | Basic (~$0) | Standard (~$20/mo) | +$20/mo |
| VNet | — | ~$0 | $0 |
| Private Endpoints | — | 2 × ~$7/mo | +$14/mo |
| DNS Zones | — | 2 × ~$0.50/mo | +$1/mo |
| **Total** | ~$0 | ~$35/mo | **+$35/mo** |

### Important: Pipeline Agent Requirement

When private endpoints are enabled, the CI/CD pipeline agent must have VNet connectivity:

| Option | Setup Effort | Cost | Use Case |
|--------|--------------|------|----------|
| **Point-to-Site VPN** | ~3 hours | VPN Gateway (~$30/mo) | Existing self-hosted agent |
| **VNet-hosted VM** | ~2 hours | VM (~$30-50/mo) | New build agent |
| **Azure DevOps Managed Agents + VNet** | ~1 hour | ~$40/agent | Microsoft-hosted with VNet injection |

### Verification

```bash
# From inside VNet (e.g., jump host)
nslookup kv-finrisk-dev.vault.azure.net
# Expected: 10.0.1.x (private IP)

# From outside VNet
nslookup kv-finrisk-dev.vault.azure.net
# Expected: Public IP (but access blocked)

# Pipeline terraform apply should succeed if agent has VNet access
terraform apply
```

---

## Configuration Summary

| Variable | Type | Default | Purpose |
|----------|------|---------|---------|
| `kv_allowed_ips` | `list(string)` | `[]` | IPs allowed to reach Key Vault |
| `aad_client_id` | `string` | `null` | Enable EasyAuth when set |
| `enable_private_endpoints` | `bool` | `false` | Enable VNet isolation |

### Example: All Features Enabled

```hcl
# terraform/environments/prod/terraform.tfvars
kv_allowed_ips           = ["203.0.113.50/32"]  # Office IP
aad_client_id            = "12345678-1234-1234-1234-123456789012"
enable_private_endpoints = true
```

### Example: Dev Environment (Default)

```hcl
# terraform/environments/dev/terraform.tfvars
kv_allowed_ips           = []
aad_client_id            = null
enable_private_endpoints = false
```

---

## Consequences

### Positive
- ✅ **Defense in Depth**: Multiple security layers
- ✅ **Zero Trust**: Explicit allowlists, no implicit trust
- ✅ **Compliance Ready**: Meets strict regulatory requirements
- ✅ **Opt-in**: No impact unless explicitly enabled

### Negative
- ⚠️ **Cost**: ~$35/mo additional for private endpoints
- ⚠️ **Complexity**: More moving parts to manage
- ⚠️ **Pipeline Changes**: VNet connectivity required for private endpoints
- ⚠️ **azapi Dependency**: EasyAuth requires azapi provider (AzureRM 4.x resource not backported)

---

## Related Decisions

- [ADR-003: Managed Identity, Network Security & Threat Model](./003-managed-identity-security.md)
- [ADR-006: Terraform Module Architecture](./006-terraform-module-architecture.md)

## References

- [Azure Container Apps Authentication](https://learn.microsoft.com/en-us/azure/container-apps/authentication)
- [Azure Private Endpoints](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview)
- [azapi Provider](https://registry.terraform.io/providers/Azure/azapi)

## Review & Approval

| Role | Name | Date | Status |
|------|------|------|--------|
| Solution Architect | [Name] | 2026-02-18 | ✅ Approved |
| Security Architect | [Name] | 2026-02-18 | ✅ Approved |

---

**Last Updated:** 2026-02-18
**Next Review:** 2026-05-18 (3 months - security-critical)
