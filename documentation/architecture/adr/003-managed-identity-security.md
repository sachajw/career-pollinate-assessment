# ADR-003: Managed Identity for Azure Authentication

**Status:** Accepted
**Date:** 2026-02-14
**Decision Makers:** Security Architecture Team
**Technical Story:** RiskShield API Integration Platform

## Context

The RiskShield integration service needs to authenticate to Azure services:
- **Azure Key Vault**: Retrieve RiskShield API key
- **Azure Container Registry**: Pull container images during deployment
- **Application Insights**: Send telemetry data

We need a secure authentication mechanism that:
- Eliminates credential management overhead
- Follows zero-trust security principles
- Provides auditable access logs
- Meets SOC 2 Type II compliance requirements
- Minimizes attack surface

We need to choose between:
1. Managed Identity (System-Assigned)
2. Managed Identity (User-Assigned)
3. Service Principal with Client Secret
4. Service Principal with Certificate
5. Connection Strings / Access Keys

## Decision

We will use **System-Assigned Managed Identity** for Azure service authentication.

## Decision Drivers

| Criterion | Weight | System MI | User MI | SP+Secret | SP+Cert | Keys |
|-----------|--------|-----------|---------|-----------|---------|------|
| **Security** | Critical | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |
| **Zero Secrets** | Critical | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐ | ⭐⭐ | ⭐ |
| **Lifecycle Simplicity** | High | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ |
| **Audit Trail** | High | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ |
| **Ease of Use** | Medium | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐ |
| **Rotation Overhead** | High | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ | ⭐⭐ |
| **Multi-Resource Reuse** | Low | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | N/A |

### Detailed Analysis

#### System-Assigned Managed Identity (Selected)
**Pros:**
- **Zero Secrets**: No passwords, keys, or certificates to manage
- **Automatic Lifecycle**: Created/deleted with the Container App
- **Azure AD Integration**: Tokens managed by Azure AD
- **RBAC-Based**: Fine-grained access control per resource
- **Audit Trail**: All access logged in Azure AD and Key Vault logs
- **No Rotation**: Tokens automatically rotated by Azure platform
- **Simple Code**: One-line authentication with DefaultAzureCredential
- **SOC 2 Compliant**: Meets password-less authentication requirements

**Cons:**
- **Single Resource**: Tied to Container App lifecycle (not an issue)
- **No Cross-Subscription**: Cannot share identity across subscriptions (not needed)
- **Regional**: Identity is regional (acceptable for our use case)

**Authentication Flow:**
```
1. Container App starts with System MI enabled
2. Azure creates identity in Azure AD (automatic)
3. Application code requests token from IMDS endpoint
4. Azure AD validates container identity
5. Azure AD returns short-lived token (1 hour)
6. Application uses token to access Key Vault
7. Key Vault validates token via RBAC
8. Access granted/denied based on role assignment
```

**Code Example:**
```typescript
import { DefaultAzureCredential } from '@azure/identity';
import { SecretClient } from '@azure/keyvault-secrets';

// Automatically uses Managed Identity in Azure
// Uses local credentials in development
const credential = new DefaultAzureCredential();

const client = new SecretClient(
  process.env.KEY_VAULT_URL,
  credential
);

const secret = await client.getSecret('RISKSHIELD_API_KEY');
console.log('API Key retrieved'); // Never log the actual value
```

**Token Caching:**
- Azure SDK automatically caches tokens
- Token refreshed 5 minutes before expiration
- No application code required

#### User-Assigned Managed Identity (Considered)
**Pros:**
- **Reusable**: Can be shared across multiple resources
- **Lifecycle Independence**: Exists independently of resources
- **Cross-Resource**: Useful for multi-service scenarios

**Cons:**
- **Additional Complexity**: Requires separate identity resource
- **Manual Lifecycle**: Must manage identity creation/deletion
- **Unnecessary**: Single service doesn't need reusable identity

**Decision:** System-Assigned is simpler for single-service scenario

#### Service Principal + Client Secret (Rejected)
**Pros:**
- **Familiar**: Well-understood authentication pattern
- **Cross-Platform**: Works outside Azure

**Cons:**
- **Secret Management**: Must store client secret securely (chicken-egg problem)
- **Rotation Overhead**: Secrets expire, require rotation (90 days)
- **Security Risk**: Secret exposure risk
- **SOC 2 Gap**: Password-based authentication less preferred

**Fatal Flaw:** Requires storing a secret to retrieve secrets (defeats purpose)

#### Service Principal + Certificate (Rejected)
**Pros:**
- **More Secure**: Better than client secret
- **Longer Expiration**: Certificates valid 1-2 years

**Cons:**
- **Certificate Management**: Complex certificate lifecycle
- **Storage Overhead**: Must store certificate file
- **Rotation**: Manual certificate renewal required
- **Complexity**: More complex than Managed Identity

**Decision:** Unnecessary complexity when MI is available

#### Connection Strings / Access Keys (Rejected)
**Pros:**
- **Simple**: Easy to understand
- **Universal**: Works everywhere

**Cons:**
- **Highly Insecure**: Static credentials, no rotation
- **No Audit Trail**: Cannot trace who accessed what
- **Non-Compliant**: Fails SOC 2 audit
- **Blast Radius**: Compromised key = full access

**Decision:** Security anti-pattern, never use for production

## Decision Rationale

### Zero-Trust Security Model

Managed Identity aligns with zero-trust principles:

```
❌ Traditional Model (Service Principal):
   Application → Store SP secret in env var → Access Key Vault

   Risks:
   - Secret exposed in environment variables
   - Secret visible in container logs
   - Secret stored in Azure DevOps variable group
   - No credential rotation

✅ Managed Identity Model:
   Application → Request token from IMDS → Access Key Vault

   Benefits:
   - No secrets in code or config
   - Short-lived tokens (1 hour)
   - Automatic rotation
   - Audit trail in Azure AD
```

### Compliance Benefits

**SOC 2 Type II Requirements:**
- ✅ **CC6.1** - Logical access control: RBAC enforced
- ✅ **CC6.2** - Authentication management: Password-less
- ✅ **CC6.6** - Logical access removal: Automatic on resource deletion
- ✅ **CC6.7** - Access audit: Azure AD logs every token request

**ISO 27001 Controls:**
- ✅ **A.9.2.1** - User registration: Automated by Azure
- ✅ **A.9.2.4** - Secret information management: No secrets to manage
- ✅ **A.9.4.3** - Password management: Not applicable (password-less)

### Attack Surface Reduction

**Threat Model Comparison:**

| Threat | Service Principal | Managed Identity |
|--------|------------------|------------------|
| **Secret Exposure in Logs** | High Risk | No Risk (no secrets) |
| **Credential Theft from Storage** | High Risk | No Risk (no storage) |
| **Insider Threat** | Medium Risk | Low Risk (RBAC audit) |
| **Credential Stuffing** | Low Risk | No Risk (no passwords) |
| **Token Replay** | Medium Risk | Low Risk (1hr expiry) |
| **Compromised DevOps Pipeline** | High Risk | Low Risk (no secrets) |

## Implementation Details

### Terraform Configuration

```hcl
# Container App with System-Assigned Managed Identity
resource "azurerm_container_app" "risk_scoring" {
  name                         = "ca-risk-scoring-${var.environment}"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name

  identity {
    type = "SystemAssigned"  # Enable Managed Identity
  }
}

# Grant Key Vault access to the Managed Identity
resource "azurerm_role_assignment" "keyvault_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"  # Read-only access
  principal_id         = azurerm_container_app.risk_scoring.identity[0].principal_id
}

# Grant ACR pull access (for container image pulls)
resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_container_app.risk_scoring.identity[0].principal_id
}

# Key Vault configured for RBAC (not access policies)
resource "azurerm_key_vault" "main" {
  name                       = "kv-riskscoring-${var.environment}"
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"

  enable_rbac_authorization  = true  # Use RBAC instead of access policies
  purge_protection_enabled   = true
  soft_delete_retention_days = 90
}
```

### Application Code Pattern

```typescript
// config/azure.ts
import { DefaultAzureCredential } from '@azure/identity';

// DefaultAzureCredential automatically tries (in order):
// 1. Environment variables (local dev with service principal)
// 2. Managed Identity (Azure runtime)
// 3. Azure CLI (local dev)
// 4. Visual Studio Code (local dev)
export const credential = new DefaultAzureCredential({
  // Optional: Add logging for troubleshooting
  loggingOptions: {
    allowLoggingAccountIdentifiers: true,
    enableUnsafeSupportLogging: true
  }
});

// services/keyvault.service.ts
import { SecretClient } from '@azure/keyvault-secrets';
import { credential } from '../config/azure';
import { logger } from '../utils/logger';

export class KeyVaultService {
  private client: SecretClient;
  private secretCache: Map<string, { value: string; expiresAt: number }>;

  constructor(vaultUrl: string) {
    this.client = new SecretClient(vaultUrl, credential);
    this.secretCache = new Map();
  }

  async getSecret(secretName: string): Promise<string> {
    // Check cache (5-minute TTL)
    const cached = this.secretCache.get(secretName);
    if (cached && Date.now() < cached.expiresAt) {
      logger.debug('Secret retrieved from cache', { secretName });
      return cached.value;
    }

    // Fetch from Key Vault
    try {
      const secret = await this.client.getSecret(secretName);

      // Cache for 5 minutes
      this.secretCache.set(secretName, {
        value: secret.value!,
        expiresAt: Date.now() + 5 * 60 * 1000
      });

      logger.info('Secret retrieved from Key Vault', {
        secretName,
        version: secret.properties.version
      });

      return secret.value!;
    } catch (error) {
      logger.error('Failed to retrieve secret', {
        secretName,
        error: error.message
      });
      throw error;
    }
  }
}
```

### Local Development

**Problem:** Managed Identity doesn't work locally

**Solution:** DefaultAzureCredential fallback chain

```bash
# Local Development Setup

# Option 1: Azure CLI (Recommended)
az login
az account set --subscription "<subscription-id>"

# Option 2: Service Principal (for CI/CD)
export AZURE_TENANT_ID="<tenant-id>"
export AZURE_CLIENT_ID="<client-id>"
export AZURE_CLIENT_SECRET="<client-secret>"  # Only for dev SP
```

**Credential Chain Order:**
1. **Environment Variables** (CI/CD pipelines)
2. **Managed Identity** (Azure runtime) ✅ Production
3. **Azure CLI** (Local development) ✅ Developer machines
4. **Azure PowerShell** (Local development)
5. **Visual Studio Code** (IDE integration)

### Monitoring & Auditing

**Key Vault Diagnostic Settings:**
```hcl
resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  name                       = "keyvault-audit-logs"
  target_resource_id         = azurerm_key_vault.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "AuditEvent"  # All access attempts
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
```

**Query Key Vault Access Logs:**
```kql
// Log Analytics Query
AzureDiagnostics
| where ResourceType == "VAULTS"
| where OperationName == "SecretGet"
| project TimeGenerated, CallerIPAddress, identity_claim_appid_g,
          properties_s, resultSignature_s
| order by TimeGenerated desc
```

**Alert on Suspicious Access:**
```hcl
resource "azurerm_monitor_metric_alert" "keyvault_unauthorized" {
  name                = "keyvault-unauthorized-access"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_key_vault.main.id]
  description         = "Alert on unauthorized Key Vault access attempts"

  criteria {
    metric_namespace = "Microsoft.KeyVault/vaults"
    metric_name      = "ServiceApiResult"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 5

    dimension {
      name     = "ActivityName"
      operator = "Include"
      values   = ["SecretGet"]
    }

    dimension {
      name     = "StatusCode"
      operator = "Include"
      values   = ["403"]  # Forbidden
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.security.id
  }
}
```

## Security Best Practices

### 1. Principle of Least Privilege
```hcl
# ❌ BAD: Overly permissive role
resource "azurerm_role_assignment" "bad" {
  role_definition_name = "Key Vault Administrator"  # Too much access!
  principal_id         = azurerm_container_app.app.identity[0].principal_id
}

# ✅ GOOD: Minimal required permissions
resource "azurerm_role_assignment" "good" {
  role_definition_name = "Key Vault Secrets User"  # Read-only
  principal_id         = azurerm_container_app.app.identity[0].principal_id
}
```

### 2. Secret Caching Strategy
- **Cache Duration**: 5 minutes (balance freshness vs. Key Vault calls)
- **Cache Invalidation**: Clear on secret rotation events
- **Fallback**: If Key Vault unavailable, use cached value with warning

### 3. Error Handling
```typescript
try {
  const apiKey = await keyVaultService.getSecret('RISKSHIELD_API_KEY');
} catch (error) {
  if (error.statusCode === 403) {
    // RBAC permission issue - alert security team
    logger.error('RBAC permission denied', { error });
  } else if (error.statusCode === 404) {
    // Secret not found - configuration issue
    logger.error('Secret not found', { error });
  } else {
    // Key Vault unavailable - use cached secret if available
    logger.warn('Key Vault unavailable, using cache', { error });
  }
  throw error;
}
```

### 4. Rotation Readiness
Even though MI doesn't require rotation, secrets in Key Vault do:

```typescript
// Graceful secret rotation handling
class SecretRotationAwareService {
  private currentSecret: string;
  private nextSecret: string | null = null;

  async rotateSecret(newSecretVersion: string): Promise<void> {
    // Fetch new secret version
    this.nextSecret = await keyVault.getSecret('API_KEY', newSecretVersion);

    // Test new secret
    const isValid = await this.validateSecret(this.nextSecret);

    if (isValid) {
      // Promote to current
      this.currentSecret = this.nextSecret;
      this.nextSecret = null;
      logger.info('Secret rotation completed');
    } else {
      logger.error('Secret rotation failed - new secret invalid');
      throw new Error('Secret rotation validation failed');
    }
  }
}
```

## Disaster Recovery

**Scenario:** Azure AD outage affecting token issuance

**Mitigation:**
1. **Secret Caching**: 5-minute cache provides resilience
2. **Graceful Degradation**: Continue operating with cached secrets
3. **Monitoring**: Alert on repeated Key Vault failures
4. **Manual Override**: Emergency procedure to inject secrets (break-glass)

**Break-Glass Procedure:**
```bash
# Emergency secret injection (documented, audited)
# Only use during Azure AD outage
kubectl create secret generic risk-scoring-secrets \
  --from-literal=RISKSHIELD_API_KEY="${EMERGENCY_API_KEY}" \
  --namespace risk-scoring

# Restart pods to pick up emergency secret
kubectl rollout restart deployment/risk-scoring-api
```

## Cost Impact

**Key Vault Costs:**
- **Secret Operations**: $0.03 per 10,000 transactions
- **Expected Usage**: 1,000 calls/day (with caching)
- **Monthly Cost**: ~$0.09

**Managed Identity:**
- **Cost**: $0 (included with Azure AD)

**Total Additional Cost:** Negligible (~$0.10/month)

## Migration from Existing Authentication

If migrating from Service Principal:

**Phase 1: Parallel Run (Week 1)**
- Add Managed Identity to Container App
- Keep existing Service Principal
- Monitor MI authentication success rate

**Phase 2: Traffic Shift (Week 2)**
- DefaultAzureCredential automatically prefers MI
- Monitor error rates
- Keep SP as fallback

**Phase 3: Cleanup (Week 3)**
- Remove Service Principal environment variables
- Revoke Service Principal access
- Update documentation

## Related Decisions

- [ADR-001: Azure Container Apps](./001-azure-container-apps.md)
- [ADR-004: Terraform for Infrastructure as Code](./004-terraform-iac.md)

## References

- [Azure Managed Identities Overview](https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview)
- [DefaultAzureCredential Documentation](https://learn.microsoft.com/en-us/javascript/api/@azure/identity/defaultazurecredential)
- [Key Vault RBAC Guide](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide)
- [SOC 2 Compliance Guide](https://www.aicpa.org/soc2)

## Review & Approval

| Role | Name | Date | Status |
|------|------|------|--------|
| Solution Architect | [Name] | 2026-02-14 | ✅ Approved |
| Security Architect | [Name] | 2026-02-14 | ✅ Approved |
| Compliance Officer | [Name] | 2026-02-14 | ✅ Approved |
| Platform Engineering Lead | [Name] | 2026-02-14 | ✅ Approved |

---

**Last Updated:** 2026-02-14
**Next Review:** 2026-05-14 (3 months - security-critical decision)
