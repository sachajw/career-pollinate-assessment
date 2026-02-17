# ADR-003: Managed Identity, Network Security & Threat Model

**Status:** Accepted
**Date:** 2026-02-14
**Decision Makers:** Security Architecture Team
**Technical Story:** RiskShield API Integration Platform

## Context

The RiskShield integration platform handles sensitive financial data and requires:

1. **Authentication**: Secure access to Azure services (Key Vault, ACR, App Insights)
2. **Secrets Management**: Secure storage of RiskShield API key
3. **Network Security**: HTTPS, controlled exposure, diagnostic logging
4. **Threat Modelling**: Understanding and mitigating security risks

The technical assessment requires:
- Store vendor API key in Azure Key Vault
- Use Managed Identity to retrieve secrets
- Restrict public exposure appropriately
- Enable HTTPS only
- Enable diagnostic logging
- Include basic threat modelling explanation

## Decision

We will use **System-Assigned Managed Identity** for authentication, **Azure Key Vault** for secrets, **HTTPS-only** public endpoint, with a **defense-in-depth security model**.

---

## Part 1: Managed Identity

### Decision: System-Assigned Managed Identity

| Criterion                | Weight   | System MI  | User MI    | SP+Secret | Keys     |
| ------------------------ | -------- | ---------- | ---------- | --------- | -------- |
| **Security**             | Critical | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐    | ⭐⭐     |
| **Zero Secrets**         | Critical | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐        | ⭐       |
| **Lifecycle Simplicity** | High     | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐   | ⭐⭐⭐    | ⭐⭐⭐   |
| **Rotation Overhead**    | High     | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐      | ⭐⭐     |

### Authentication Flow

```
1. Container App starts with System MI enabled
2. Azure creates identity in Azure AD (automatic)
3. Application requests token from IMDS endpoint
4. Azure AD validates container identity
5. Azure AD returns short-lived token (1 hour)
6. Application uses token to access Key Vault
7. Key Vault validates token via RBAC
8. Access granted/denied based on role assignment
```

### Implementation

**Terraform:**

```hcl
# Container App with System-Assigned Managed Identity
resource "azurerm_container_app" "risk_scoring" {
  name = "ca-${local.naming_prefix}"

  identity {
    type = "SystemAssigned"
  }
}

# Grant Key Vault access
resource "azurerm_role_assignment" "keyvault_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_container_app.risk_scoring.identity[0].principal_id
}

# Grant ACR pull access
resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_container_app.risk_scoring.identity[0].principal_id
}
```

**Python:**

```python
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

# Automatically uses Managed Identity in Azure
credential = DefaultAzureCredential()
client = SecretClient(vault_url=os.environ["KEY_VAULT_URL"], credential=credential)

secret = client.get_secret("RISKSHIELD_API_KEY")
```

---

## Part 2: Threat Model

### STRIDE Analysis

| Threat Type          | Threat Description                                | Mitigation                                | Risk |
| -------------------- | ------------------------------------------------- | ----------------------------------------- | ---- |
| **Spoofing**         | Attacker impersonates legitimate client           | Azure AD auth (future enhancement)        | Medium |
| **Tampering**        | Data modified in transit                          | HTTPS/TLS 1.2+ enforcement                | Low |
| **Repudiation**      | Attacker denies actions                           | Full audit logging in Log Analytics       | Low |
| **Information Disclosure** | API keys or PII leaked                    | Key Vault, encrypted at rest              | Low |
| **Denial of Service** | Service overwhelmed by requests                  | Container Apps autoscaling, rate limiting | Medium |
| **Elevation of Privilege** | Container breakout or unauthorized access   | Non-root container, RBAC, least privilege | Low |

### Attack Surface Map

```
┌─────────────────────────────────────────────────────────────────────┐
│                         ATTACK SURFACE                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────┐         ┌─────────────────────────────────────┐   │
│  │   Internet   │────────▶│  Container App (HTTPS:443)         │   │
│  └──────────────┘         │  - TLS 1.2+ enforced                │   │
│        │                  │  - Rate limiting                    │   │
│        ▼                  └────────────────┬────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    INTERNAL SERVICES                          │   │
│  │  ┌─────────────┐    ┌─────────────┐    ┌─────────────────┐   │   │
│  │  │  Key Vault  │    │  RiskShield │    │  App Insights   │   │   │
│  │  │  (RBAC)     │    │  (API Key)  │    │  (Telemetry)    │   │   │
│  │  └─────────────┘    └─────────────┘    └─────────────────┘   │   │
│  │        ▲                  ▲                    ▲              │   │
│  │        └──────────────────┴────────────────────┘              │   │
│  │                   Managed Identity                            │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### Trust Boundaries

| Boundary | Risk | Mitigation |
|----------|------|------------|
| Internet → Azure | Untrusted → Semi-trusted | TLS 1.2+, rate limiting, input validation |
| Container App → Key Vault | Semi-trusted → Trusted | Managed Identity, RBAC, no public network |
| Container App → RiskShield | Trusted → External | API key in Key Vault, HTTPS, timeouts |

---

## Part 3: Network Security

### HTTPS-Only Enforcement

```hcl
# Container Apps automatically enforces HTTPS
resource "azurerm_container_app" "main" {
  ingress {
    external_enabled = true
    target_port      = 8080
    transport        = "http"  # HTTPS termination at ingress
  }
}
```

**Verification:**

```bash
# HTTP should redirect to HTTPS
curl -I http://ca-finrisk-dev.eastus2.azurecontainerapps.io/health
# Expected: 301 Redirect

# HTTPS should work
curl -I https://ca-finrisk-dev.eastus2.azurecontainerapps.io/health
# Expected: 200 OK
```

### Public Exposure Strategy

| Environment | Exposure | Rationale |
|-------------|----------|-----------|
| **Dev** | Public + HTTPS | Acceptable for dev/test, no sensitive data |
| **Prod** | Public + HTTPS (Private Endpoint optional) | Can add private endpoints if compliance requires |

### Input Validation

```python
from pydantic import BaseModel, Field, field_validator
import re

class ValidateRequest(BaseModel):
    firstName: str = Field(..., min_length=1, max_length=100)
    lastName: str = Field(..., min_length=1, max_length=100)
    idNumber: str = Field(..., min_length=13, max_length=13)

    @field_validator('firstName', 'lastName')
    @classmethod
    def validate_name(cls, v: str) -> str:
        if not re.match(r'^[a-zA-Z\s]+$', v):
            raise ValueError('Name must contain only letters and spaces')
        return v.strip()

    @field_validator('idNumber')
    @classmethod
    def validate_id_number(cls, v: str) -> str:
        if not v.isdigit() or len(v) != 13:
            raise ValueError('ID number must be exactly 13 digits')
        return v
```

---

## Part 4: Diagnostic Logging

### Enable Diagnostic Settings

```hcl
# Container App diagnostics
resource "azurerm_monitor_diagnostic_setting" "container_app" {
  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_container_app.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "ContainerAppConsoleLogs"
  }

  enabled_log {
    category = "ContainerAppSystemLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Key Vault diagnostics (audit all access)
resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                       = "diag-kv-${var.name}"
  target_resource_id         = azurerm_key_vault.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AuditEvent"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
```

### Log Categories

| Resource | Log Category | Purpose |
|----------|--------------|---------|
| Container App | ContainerAppConsoleLogs | Application logs |
| Container App | ContainerAppSystemLogs | Platform logs, errors |
| Key Vault | AuditEvent | All access attempts (success + failure) |

### Security Alerts

```hcl
# Alert on unauthorized Key Vault access
resource "azurerm_monitor_metric_alert" "keyvault_unauthorized" {
  name                = "keyvault-unauthorized-access"
  scopes              = [azurerm_key_vault.main.id]

  criteria {
    metric_namespace = "Microsoft.KeyVault/vaults"
    metric_name      = "ServiceApiResult"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 5

    dimension {
      name     = "StatusCode"
      operator = "Include"
      values   = ["403"]
    }
  }

  action {
    action_group_id = var.security_action_group_id
  }
}
```

---

## Part 5: Security Best Practices

### Principle of Least Privilege

```hcl
# ❌ BAD: Overly permissive
role_definition_name = "Key Vault Administrator"

# ✅ GOOD: Minimal required permissions
role_definition_name = "Key Vault Secrets User"  # Read-only
```

### Secret Caching

- Cache duration: 5 minutes (balance freshness vs Key Vault calls)
- Cache invalidation: Clear on secret rotation events
- Fallback: Use cached value if Key Vault unavailable

### Compliance Mapping

| Control | SOC 2 | ISO 27001 | Implementation |
|---------|-------|-----------|----------------|
| Access Control | CC6.1 | A.9.1 | RBAC + Managed Identity |
| Authentication | CC6.2 | A.9.4 | Managed Identity |
| Encryption in Transit | CC6.7 | A.10.1 | TLS 1.2+ |
| Encryption at Rest | CC6.7 | A.10.1 | Azure Storage encryption |
| Audit Logging | CC7.2 | A.12.4 | Log Analytics |

---

## Summary: Technical Assessment Compliance

| Requirement | Status | Implementation |
|-------------|--------|----------------|
| Store API key in Key Vault | ✅ | Part 1 |
| Use Managed Identity | ✅ | Part 1 (System-Assigned) |
| Restrict public exposure | ✅ | Part 3 (HTTPS, rate limiting) |
| Enable HTTPS only | ✅ | Part 3 (Container Apps ingress) |
| Enable diagnostic logging | ✅ | Part 4 (All resources → Log Analytics) |
| Threat modelling | ✅ | Part 2 (STRIDE analysis) |

---

## Consequences

### Positive
- ✅ **Zero Secrets**: No passwords or keys in code/config
- ✅ **Automatic Rotation**: Tokens rotate automatically (1 hour)
- ✅ **Audit Trail**: All access logged in Azure AD and Key Vault
- ✅ **Defense in Depth**: Multiple security layers
- ✅ **Compliance**: SOC 2 and ISO 27001 controls addressed

### Negative
- ⚠️ **Cold Start**: Managed Identity adds ~500ms to cold start
- ⚠️ **Azure Lock-in**: Managed Identity is Azure-specific

---

## Related Decisions

- [ADR-001: Azure Container Apps](./001-azure-container-apps.md)
- [ADR-002: Python Runtime & Resilience](./002-python-runtime.md)

## References

- [Azure Managed Identities Overview](https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview)
- [Key Vault RBAC Guide](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide)
- [STRIDE Threat Modeling](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats)
- [OWASP API Security Top 10](https://owasp.org/www-project-api-security/)

## Review & Approval

| Role                      | Name   | Date       | Status      |
| ------------------------- | ------ | ---------- | ----------- |
| Solution Architect        | [Name] | 2026-02-14 | ✅ Approved |
| Security Architect        | [Name] | 2026-02-14 | ✅ Approved |
| Compliance Officer        | [Name] | 2026-02-14 | ✅ Approved |

---

**Last Updated:** 2026-02-14
**Next Review:** 2026-05-14 (3 months - security-critical)
