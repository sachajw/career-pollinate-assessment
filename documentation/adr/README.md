# Architecture Decision Records (ADRs)

This directory contains Architecture Decision Records documenting key architectural decisions for the RiskShield API Integration Platform.

## What is an ADR?

An Architecture Decision Record (ADR) captures an important architectural decision made along with its context and consequences. ADRs help teams understand why decisions were made and provide a historical record for future reference.

## ADR Format

Each ADR follows this structure:

- **Status**: Proposed, Accepted, Deprecated, Superseded
- **Context**: The problem or situation requiring a decision
- **Decision**: The chosen solution
- **Decision Drivers**: Criteria used to evaluate options
- **Consequences**: Positive, negative, and neutral outcomes
- **Alternatives**: Options considered but not selected

## Active ADRs

| ADR | Title | Status | Date | Impact |
|-----|-------|--------|------|--------|
| [001](./001-azure-container-apps.md) | Azure Container Apps for Compute Platform | ✅ Accepted | 2026-02-14 | 🔴 Critical |
| [002](./002-python-runtime.md) | Python Runtime, Resilience & Observability | ✅ Accepted | 2026-02-14 | 🔴 Critical |
| [003](./003-managed-identity-security.md) | Managed Identity, Network Security & Threat Model | ✅ Accepted | 2026-02-14 | 🔴 Critical |
| [005](./005-docker-container-strategy.md) | Docker Container Strategy | ✅ Accepted | 2026-02-14 | 🟠 High |
| [006](./006-terraform-module-architecture.md) | Terraform Module Architecture | ✅ Accepted | 2026-02-14 | 🔴 Critical |
| [007](./007-cicd-pipeline-strategy.md) | CI/CD Pipeline Strategy (Azure DevOps) | ✅ Accepted | 2026-02-14 | 🔴 Critical |
| [008](./008-bonus-security-enhancements.md) | Bonus Security Enhancements | ✅ Accepted | 2026-02-18 | 🟠 High |

## Technical Assessment Coverage

These ADRs comprehensively address all technical assessment requirements:

| Assessment Requirement | ADR Coverage |
|------------------------|--------------|
| **1. Application Layer** (language, error handling, logging, timeouts, retries, correlation IDs) | [ADR-002](./002-python-runtime.md) |
| **2. Containerisation** (multi-stage, non-root, small image, healthcheck) | [ADR-005](./005-docker-container-strategy.md) |
| **3. Infrastructure** (Terraform modules, remote state, environments, naming) | [ADR-006](./006-terraform-module-architecture.md) |
| **4. Security** (Key Vault, Managed Identity, HTTPS, diagnostics, threat model) | [ADR-003](./003-managed-identity-security.md) |
| **4. Security (Bonus)** (Network restrictions, Azure AD auth, Private endpoints) | [ADR-008](./008-bonus-security-enhancements.md) |
| **5. CI/CD Pipeline** (3-stage, service connections, variable groups, environments) | [ADR-007](./007-cicd-pipeline-strategy.md) |
| **Compute Platform** | [ADR-001](./001-azure-container-apps.md) |

## Decision Impact Levels

- 🔴 **Critical**: Core architectural decisions affecting the entire platform
- 🟠 **High**: Significant decisions affecting major components
- 🟡 **Medium**: Important decisions with localized impact
- 🟢 **Low**: Minor decisions or implementation details

## ADR Lifecycle

```
Proposed → Under Review → Accepted → Implemented
                    ↓
                Rejected
                    ↓
               Deprecated (if later superseded)
```

## Review Schedule

- **Critical Decisions**: Reviewed every 3 months
- **High Impact Decisions**: Reviewed every 6 months
- **Medium/Low Impact**: Reviewed annually

## Creating a New ADR

1. Copy the ADR template: `cp _template.md 00X-your-decision.md`
2. Fill in all sections with detailed analysis
3. Submit for review via Pull Request
4. Update this README with the new ADR entry
5. Present in architecture review meeting
6. After approval, update status to "Accepted"

## Related Documentation

- [Solution Architecture Document](../solution-architecture.md)
- [API Specification](../../api/API_SPECIFICATION.md)

---

**Last Updated:** 2026-02-18
**Maintained By:** Solution Architecture Team
