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

**Application Structure:**
```
app/
├── src/
│   ├── api/              # API routes and endpoints
│   │   └── v1/
│   ├── models/           # Pydantic models
│   │   └── validation.py
│   ├── services/         # Business logic
│   │   ├── keyvault.py
│   │   └── riskshield.py
│   ├── core/             # Config, logging, security
│   └── main.py           # FastAPI app entry point
├── tests/
│   ├── unit/
│   └── integration/
├── Dockerfile
├── .dockerignore
├── README.md
└── pyproject.toml
```

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

**Multi-Stage Build:**
```dockerfile
# Stage 1: Builder - Install dependencies with uv
FROM python:3.13-slim AS builder
RUN pip install --no-cache-dir uv
WORKDIR /app
COPY pyproject.toml README.md ./
RUN uv venv /opt/venv && \
    . /opt/venv/bin/activate && \
    uv pip install --no-cache -e .

# Stage 2: Runtime - Minimal production image
FROM python:3.13-slim AS production
RUN groupadd -r appuser && useradd -r -g appuser appuser
WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY src/ ./src/
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8080
USER appuser
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')"
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8080"]
```

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

| Environment | Purpose | Config |
|-------------|---------|--------|
| **Dev** | Development/testing | Manual deploy, ephemeral |
| **Staging** | Pre-prod validation | Auto-deploy from main |
| **Prod** | Production workloads | Manual approval required |

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
- **Limits**: Min 2, Max 10 (prod)

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

**Development Environment:**
```
Azure Container App         $30   (0.5 vCPU, 1Gi, scale to zero)
Azure Container Registry    $5    (Basic tier)
Key Vault                   $3    (Standard, <10k operations)
Log Analytics               $10   (1GB ingestion/day)
Application Insights        $5    (Included with Log Analytics)
Storage Account (TF state)  $1
─────────────────────────────────
Total:                      ~$54/month
```

**Production Environment:**
```
Azure Container App         $180  (2-4 replicas, always-on)
Azure Container Registry    $100  (Premium, geo-replication)
Key Vault                   $15   (Standard + Private Endpoint)
Log Analytics               $100  (10GB ingestion/day)
Application Insights        $30
Azure Front Door            $50   (WAF + routing)
Storage Account             $5
─────────────────────────────────
Total:                      ~$480/month
```

**Cost Optimization Strategies:**
- **Dev**: Scale to zero during off-hours (-50%)
- **Reserved Instances**: Not applicable (consumption-based)
- **Log Retention**: 30 days dev, 90 days prod (-40% storage)
- **Image Pruning**: Automated cleanup of old images (-20% ACR costs)

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

## Success Metrics

### Technical Metrics
- ✅ Deployment time: < 10 minutes
- ✅ Infrastructure provisioning: < 5 minutes (Terraform)
- ✅ Test coverage: > 80%
- ✅ Security scan: 0 critical vulnerabilities
- ✅ Image size: < 150MB

### Business Metrics
- ✅ Loan processing time: Reduced by 40%
- ✅ Manual review reduction: 60% of applications auto-scored
- ✅ Operational cost: < $500/month (prod)
- ✅ Uptime: 99.9% availability

---

## Next Steps

1. **Phase 1: Foundation** (Week 1)
   - Set up Azure DevOps project
   - Configure Terraform remote state
   - Implement base API with health checks

2. **Phase 2: Core Features** (Week 2)
   - Integrate RiskShield API
   - Implement retry/timeout logic
   - Add correlation ID tracking

3. **Phase 3: Security** (Week 2-3)
   - Configure Key Vault + Managed Identity
   - Implement secret rotation
   - Security scanning in pipeline

4. **Phase 4: Observability** (Week 3)
   - Configure Application Insights
   - Set up dashboards and alerts
   - Load testing and optimization

5. **Phase 5: Production Hardening** (Week 4)
   - Front Door + WAF configuration
   - DR testing and documentation
   - Security audit and compliance review

---

*Document Version: 1.0*
*Last Updated: 2026-02-14*
*Author: Solution Architect*
