# Solution Architecture: RiskShield API Integration Platform

## Executive Summary

This document outlines the solution architecture for FinSure Capital's RiskShield API integration platform. The solution provides a secure, scalable, cloud-native integration service for validating loan applicants through third-party risk scoring.

**Architecture Principles:**
- **Cloud-Native First**: Leverage Azure PaaS services for reduced operational overhead
- **Security by Design**: Zero-trust model with managed identities and key vault integration
- **Infrastructure as Code**: Fully automated, repeatable deployments
- **Observability**: Comprehensive logging, monitoring, and tracing
- **Resilience**: Retry logic, circuit breakers, and graceful degradation

---

## High-Level Architecture

### System Context

```
┌─────────────────┐
│   Loan          │
│   Origination   │──┐
│   System        │  │
└─────────────────┘  │
                     │ POST /validate
                     ▼
              ┌──────────────────┐
              │  Azure Front     │
              │  Door / APIM     │◄─── HTTPS Only
              └────────┬─────────┘
                       │
                       ▼
              ┌──────────────────┐
              │  Risk Scoring    │
              │  Integration     │
              │  Service         │
              │  (Container App) │
              └────────┬─────────┘
                       │
         ┌─────────────┼─────────────┐
         │             │             │
         ▼             ▼             ▼
    ┌────────┐   ┌─────────┐   ┌─────────┐
    │  Key   │   │  App    │   │  Log    │
    │  Vault │   │ Insights│   │Analytics│
    └────────┘   └─────────┘   └─────────┘
         │
         │ Secrets
         ▼
    ┌──────────────────┐
    │   RiskShield     │
    │   External API   │
    └──────────────────┘
```

---

## Component Architecture

### 1. Application Layer

**Technology Selection: Python 3.13 (FastAPI)**

**Rationale:**
- Fastest development with automatic API documentation
- Excellent Pydantic validation for data integrity
- Native async/await support for I/O operations
- Comprehensive Azure SDK support
- Strong type hints with Python 3.13 enhancements
- JIT compiler for 10-30% performance boost (experimental)
- Industry standard for FinTech data processing

**Key Features:**
- **Correlation IDs**: UUID v4 for request tracing
- **Structured Logging**: JSON format with correlation context
- **Retry Logic**: Exponential backoff (3 attempts, 1s/2s/4s delays)
- **Circuit Breaker**: Fail fast after 5 consecutive failures
- **Timeout Handling**: 30s external API timeout
- **Health Checks**: `/health` (liveness) and `/ready` (readiness)
- **Graceful Shutdown**: 30s drain period for in-flight requests

---

### 2. Container Strategy

**Base Image: Python 3.13 Slim**

**Security Features:**
- Non-root user (appuser:1001)
- Minimal attack surface (slim base)
- No unnecessary packages
- Read-only filesystem where possible
- Security scanning with Bandit

**Image Optimization:**
- Multi-stage builds reduce final image size by ~60%
- Target: < 200MB final image
- Layer caching optimization
- `.dockerignore` excludes dev dependencies and caches

---

### 3. Azure Infrastructure Architecture

#### Compute: Azure Container Apps (Recommended)

**Why Container Apps over App Service:**

| Criteria | Container Apps | App Service | Decision |
|----------|---------------|-------------|----------|
| Cost | Pay per second, scale to zero | Always-on minimum cost | ✅ Container Apps |
| Scaling | Kubernetes-based, event-driven | Basic autoscale | ✅ Container Apps |
| Cold Start | ~2s | N/A | ⚖️ Acceptable |
| Simplicity | Managed K8s abstraction | Simpler | ⚖️ Similar |
| KEDA Support | Native | No | ✅ Container Apps |
| Dapr Integration | Native | No | ✅ Future-proof |

**Configuration:**
- **Min Replicas**: 1 (dev), 2 (prod)
- **Max Replicas**: 10
- **CPU/Memory**: 0.5 vCPU / 1Gi RAM
- **Scaling Rule**: HTTP concurrency (100 requests/replica)
- **Ingress**: External, HTTPS only
- **Session Affinity**: Disabled (stateless)

#### Alternative: Azure App Service

If organizational preference for App Service:
- **Plan**: Premium v3 P1v3
- **Always On**: Enabled
- **Auto-scale**: CPU > 70% (min: 2, max: 10)
- **Deployment Slots**: Blue/Green deployments

---

### 4. Security Architecture

#### Identity & Access Management

**Managed Identity Flow:**
```
Container App (System MI)
    │
    ├──► Key Vault (RBAC: Key Vault Secrets User)
    │       └──► Retrieve: RISKSHIELD_API_KEY
    │
    └──► ACR (RBAC: AcrPull)
            └──► Pull container images
```

**Key Vault Configuration:**
- **Soft Delete**: Enabled (90 days)
- **Purge Protection**: Enabled
- **Network**: Private Endpoint (prod), Service Endpoint (dev)
- **Access Policy**: RBAC-based (not legacy access policies)
- **Rotation**: 90-day secret rotation policy
- **Monitoring**: Audit logs to Log Analytics

**Secrets Management:**
```
RISKSHIELD_API_KEY → Key Vault Secret
  ├── Version: Auto-rotate every 90 days
  ├── Access: Container App Managed Identity
  └── Audit: All access logged
```

#### Network Security

**Development Environment:**
```
Internet ──HTTPS──► Container App (Public Ingress)
                        │
                        ├──► Key Vault (Service Endpoint)
                        └──► RiskShield API (Internet)
```

**Production Environment (Enhanced):**
```
Internet ──HTTPS──► Azure Front Door / APIM
                        │ (WAF, DDoS, Rate Limiting)
                        ▼
                    Container App (Internal Ingress)
                        │ (VNet Integration)
                        ├──► Key Vault (Private Endpoint)
                        └──► RiskShield API (NAT Gateway)
```

**Network Controls:**
- **HTTPS Only**: TLS 1.2+ enforced
- **CORS**: Whitelist allowed origins
- **IP Restrictions**: Optional IP allowlisting
- **WAF**: OWASP Top 10 protection (prod)
- **DDoS**: Azure DDoS Standard (prod)

#### Threat Model Summary

| Threat | Mitigation |
|--------|-----------|
| API Key Exposure | Key Vault + Managed Identity, no env vars |
| MITM Attacks | HTTPS only, TLS 1.2+ |
| Credential Theft | No passwords, MI-based auth |
| DDoS | Azure DDoS Standard + rate limiting |
| Injection Attacks | Input validation, parameterized queries |
| Dependency Vulnerabilities | Trivy/Snyk image scanning |
| Insider Threat | RBAC, audit logging, just-in-time access |

---

### 5. Observability Architecture

#### Logging Strategy

**Application Logs:**
```json
{
  "timestamp": "2026-02-14T15:30:00.000Z",
  "level": "info",
  "correlationId": "a1b2c3d4-...",
  "service": "risk-scoring-api",
  "operation": "validateApplicant",
  "duration": 234,
  "statusCode": 200,
  "userId": "user@example.com",
  "message": "Risk validation completed"
}
```

**Log Destinations:**
- **Application Insights**: Structured logs + custom metrics
- **Log Analytics**: Centralized log aggregation
- **Retention**: 90 days (dev), 365 days (prod)

#### Monitoring & Alerting

**Key Metrics:**
- **Availability**: Uptime % (target: 99.9%)
- **Latency**: P50, P95, P99 response times
- **Error Rate**: 4xx/5xx errors per minute
- **Dependency Health**: RiskShield API success rate
- **Resource Usage**: CPU, memory, network

**Alerts:**
- **Critical**: Error rate > 5% (PagerDuty)
- **Warning**: P95 latency > 2s (Email)
- **Info**: Deployment completed (Slack)

#### Distributed Tracing

**Application Insights SDK:**
- Automatic dependency tracking
- End-to-end transaction tracing
- Custom events for business metrics

**Trace Example:**
```
Request: POST /validate [200ms]
  ├─ Key Vault: Get Secret [50ms]
  ├─ RiskShield API: POST /score [120ms]
  └─ Response Serialization [30ms]
```

---

### 6. Deployment Architecture

#### Environment Strategy

| Environment | Purpose | Config | Status |
|-------------|---------|--------|--------|
| **Dev** | Development/testing | Manual deploy, scale-to-zero | ✅ Deployed |
| **Prod** | Production workloads | Manual approval required | 📋 Documented (quota limit) |

**Assessment Note:** For this technical assessment, only the **dev environment** is deployed due to Azure subscription quota limits (1 Container App Environment per subscription). The production configuration is fully documented and ready for deployment with increased quotas or a separate subscription.

**Branch Strategy:**
- `dev` branch → dev environment (`rg-finrisk-dev`)
- `main` branch → prod environment (`rg-finrisk-prod`) - when quotas allow

#### CI/CD Pipeline Architecture

**Pipeline Flow:**
```
┌─────────────┐
│ Code Commit │
│  (Feature)  │
└──────┬──────┘
       │
       ▼
┌─────────────────────┐
│ Stage 1: BUILD      │
│ - Lint & Format     │
│ - Unit Tests        │
│ - Build Image       │
│ - Security Scan     │
│ - Push to ACR       │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ Stage 2: INFRA      │
│ - Terraform Validate│
│ - Terraform Plan    │
│ - Cost Estimation   │
│ - Manual Approval   │◄── Prod Only
│ - Terraform Apply   │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ Stage 3: DEPLOY     │
│ - Update Container  │
│ - Health Check      │
│ - Smoke Tests       │
│ - Integration Tests │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ Stage 4: VERIFY     │
│ - Performance Tests │
│ - Security Scan     │
│ - Rollback on Fail  │
└─────────────────────┘
```

**Pipeline Features:**
- **Artifact Management**: ACR for images, Storage for Terraform state
- **Secret Management**: Variable Groups linked to Key Vault
- **Approval Gates**: Manual approval for prod deployments
- **Rollback Strategy**: Blue/green deployments with instant rollback
- **Test Automation**: Unit → Integration → E2E → Performance

---

## Data Flow Architecture

### Happy Path Flow

```
1. Client Request
   POST /validate
   {
     "firstName": "Jane",
     "lastName": "Doe",
     "idNumber": "9001011234088"
   }
   Headers:
     - X-Correlation-ID: <uuid>
     - Authorization: Bearer <token> (optional)

2. API Gateway (Container App)
   ├─ Generate/validate correlation ID
   ├─ Input validation (schema check)
   ├─ Rate limit check (100 req/min per client)
   └─ Log request received

3. Secrets Retrieval
   ├─ Check in-memory cache (5min TTL)
   └─ If miss: Fetch from Key Vault using MI

4. External API Call
   POST https://api.riskshield.com/v1/score
   Headers:
     - X-API-Key: <from Key Vault>
     - X-Correlation-ID: <uuid>
   Body:
     {
       "firstName": "Jane",
       "lastName": "Doe",
       "idNumber": "9001011234088"
     }
   Timeout: 30s
   Retry: 3 attempts with exponential backoff

5. Response Processing
   ├─ Validate response schema
   ├─ Transform to internal format
   ├─ Log response metadata
   └─ Return to client

6. Client Response
   {
     "riskScore": 72,
     "riskLevel": "MEDIUM",
     "correlationId": "a1b2c3d4-..."
   }
```

### Error Handling Flow

```
Error Scenarios:
├─ Validation Error (400)
│   └─ Return: Invalid request format
├─ RiskShield Timeout (504)
│   ├─ Retry with backoff
│   └─ After 3 attempts: Return timeout error
├─ RiskShield 5xx (502)
│   ├─ Retry with backoff
│   └─ Circuit breaker trips after 5 failures
├─ Key Vault Unavailable (503)
│   └─ Use cached secret (if available)
└─ Rate Limit Exceeded (429)
    └─ Return: Retry-After header
```

---

## Non-Functional Requirements

### Performance Targets

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Availability** | 99.9% | Application Insights |
| **Latency (P95)** | < 2s | End-to-end response time |
| **Latency (P99)** | < 5s | End-to-end response time |
| **Throughput** | 1000 req/min | Sustained load |
| **Error Rate** | < 0.1% | Application errors |
| **Cold Start** | < 3s | First request after scale-to-zero |

### Scalability

**Horizontal Scaling:**
- **Trigger**: CPU > 70% OR Request queue > 100
- **Scale Out**: +1 replica every 30s
- **Scale In**: -1 replica every 5 min (gradual)
- **Limits**: Min 0 (dev), Min 2 (prod), Max 10

**Deployed URLs:**
- **Dev (Default):** `https://ca-finrisk-dev.icydune-b53581f6.eastus2.azurecontainerapps.io`
- **Dev (Custom):** `https://finrisk-dev.pangarabbit.com`
- **Prod:** Not deployed (documented for future deployment)

**Load Testing:**
- **Tool**: Azure Load Testing / k6
- **Scenario**: 1000 concurrent users, 10 min duration
- **Success Criteria**: P95 < 2s, Error rate < 0.1%

### Security Compliance

**Standards:**
- **PCI DSS**: Not directly handling payment data (N/A)
- **SOC 2 Type II**: Audit logging, access controls
- **GDPR**: Data minimization, no PII storage
- **ISO 27001**: Security controls documentation

**Security Scanning:**
- **SAST**: SonarQube / CodeQL
- **DAST**: OWASP ZAP
- **Container Scanning**: Trivy / Snyk
- **Dependency Scanning**: Dependabot / Renovate
- **Secret Scanning**: GitGuardian / GitHub Advanced Security

### Disaster Recovery

**RTO/RPO:**
- **RTO** (Recovery Time Objective): 1 hour
- **RPO** (Recovery Point Objective): 15 minutes

**Backup Strategy:**
- **Configuration**: Terraform state (versioned in Storage)
- **Secrets**: Key Vault soft delete (90 days)
- **Code**: Git repository (GitHub/Azure Repos)
- **Container Images**: ACR geo-replication (prod)

**DR Testing:**
- **Frequency**: Quarterly
- **Scope**: Full environment rebuild from Terraform
- **Success Criteria**: < 1 hour recovery time

---

## Cost Optimization

### Estimated Monthly Costs (USD)

> Prices sourced from Azure Retail Prices API, East US 2, February 2026.

**Development Environment** (`rg-finrisk-dev`, min_replicas=0, scale-to-zero):

```
Azure Container App          ~$0    Scale-to-zero: costs only active request seconds.
                                    Consumption plan free grant covers dev traffic:
                                    180,000 vCPU-s and 360,000 GiB-s free/month.
                                    ($0.000024/vCPU-s, $0.000003/GiB-s)
Azure Container Registry      $5    Basic tier ($0.1666/day × 30 days)
Key Vault                    ~$0    Standard: $0.03/10k ops; <1,000 ops/day in dev
Log Analytics                ~$3    $2.76/GB after 5 GB free; ~0.2 GB/day = ~1 GB billable
Application Insights         ~$0    Workspace-based; counted in Log Analytics above
Storage Account (TF state)   ~$0    LRS block blob: $0.024/GB; state < 1 MB
Managed Identity              $0    Included with Azure AD
──────────────────────────────────────
Total:                        ~$8/month
```

**Production Environment** (hypothetical target, min_replicas=2, 24/7, 0.5 vCPU, 1 GiB):

```
Azure Container App          ~$72   Consumption plan, 2 replicas always-on:
                                    2,412,000 billable vCPU-s × $0.000024 = $57.89
                                    4,824,000 billable GiB-s  × $0.000003 = $14.47
Azure Container Registry     $20    Standard tier ($0.6666/day × 30 days)
Key Vault                    ~$1    ~50,000 ops/month × $0.03/10k = $0.15
Log Analytics                $28    ~500 MB/day = 15 GB/month; 10 GB billable × $2.76
Application Insights         ~$0    Workspace-based; included in Log Analytics
Azure Front Door             $35+   WAF + routing (prod target, not yet deployed)
Storage Account               $1    LRS block blob: $0.024/GB/month
──────────────────────────────────────
Total without Front Door:     ~$122/month
Total with Front Door:        ~$157/month
```

**Cost Optimization Strategies:**
- **Dev scale-to-zero**: min_replicas=0 reduces Container App cost to near zero
- **Log retention**: 30 days dev vs 90 days prod reduces Log Analytics storage cost
- **ACR Basic in dev**: $5/month vs Standard ($20) or Premium ($50)
- **Consumption plan**: No idle cost; pay only for active vCPU-seconds and GiB-seconds

---

## Technology Stack Summary

| Layer | Technology | Justification |
|-------|-----------|---------------|
| **Runtime** | Python 3.13 | Modern, async support, type hints |
| **Framework** | FastAPI | Auto docs, Pydantic validation, performance |
| **ASGI Server** | Uvicorn | Fast, production-ready ASGI server |
| **Container** | Docker (Python Slim) | Small footprint, security, portability |
| **Compute** | Azure Container Apps | Serverless K8s, cost-effective, KEDA |
| **Registry** | Azure Container Registry | Native integration, geo-replication |
| **Secrets** | Azure Key Vault | Managed, audited, RBAC-based |
| **Identity** | Managed Identity | Password-less, Azure-native |
| **Logging** | Application Insights | Full-stack APM, distributed tracing |
| **IaC** | Terraform | Multi-cloud, declarative, state mgmt |
| **CI/CD** | Azure DevOps | Native integration, YAML pipelines |
| **Testing** | pytest + httpx | Async support, comprehensive fixtures |
| **Linting** | Ruff + Mypy | Fast linting, type checking |

---

## Trade-offs & Decisions

### 1. Container Apps vs. App Service

**Decision:** Azure Container Apps

**Trade-offs:**
- ✅ Cost: Scale to zero capability
- ✅ Flexibility: Kubernetes abstraction
- ✅ Future: Dapr integration for service mesh
- ❌ Maturity: Newer service (since 2022)
- ❌ Debugging: Slightly more complex than App Service

### 2. Python vs. .NET vs. Go vs. Node.js

**Decision:** Python 3.13 (FastAPI)

**Trade-offs:**
- ✅ Development Speed: Fastest prototyping, concise syntax
- ✅ Data Validation: Pydantic provides industry-leading validation
- ✅ Auto Documentation: FastAPI generates OpenAPI specs automatically
- ✅ Team Familiarity: Standard in FinTech for data processing
- ❌ Performance: Slower than Go/Node.js (still meets requirements)
- ❌ Container Size: Larger than Node.js (~180MB vs ~120MB)

### 3. APIM vs. Front Door vs. Direct Ingress

**Decision:** Direct Ingress (dev), Front Door (prod)

**Trade-offs:**
- ✅ Simplicity: Fewer moving parts for simple use case
- ✅ Cost: Save ~$250/month on APIM
- ❌ Features: No built-in rate limiting, transformation
- ⚖️ Mitigation: Implement app-level rate limiting

### 4. Terraform vs. Bicep

**Decision:** Terraform

**Trade-offs:**
- ✅ Multi-Cloud: Portable to AWS/GCP if needed
- ✅ Ecosystem: Large module library
- ✅ State Management: Remote state built-in
- ❌ Azure Native: Bicep has better Azure integration
- ❌ Learning Curve: Slightly steeper than Bicep

---

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| RiskShield API Downtime | High | Medium | Circuit breaker, fallback response |
| Key Vault Unavailable | High | Low | Secret caching (5min TTL) |
| Cold Start Latency | Medium | High | Min replicas: 2 (prod) |
| Cost Overrun | Medium | Low | Budget alerts, auto-scaling limits |
| Security Breach | High | Low | Zero trust, MI, audit logging |
| Deployment Failure | Medium | Medium | Blue/green deployment, auto-rollback |

---

*Document Version: 1.1*
*Last Updated: 2026-02-17*
*Author: Solution Architect*
