# Interview Preparation Guide: FinRisk Platform Technical Assessment

## Table of Contents

- [Quick Reference](#quick-reference)
- [Section 1: Project Overview](#section-1-project-overview)
- [Section 2: Architecture Decisions](#section-2-architecture-decisions)
  - [Why Azure Container Apps?](#q-why-azure-container-apps-over-app-service-or-aks)
  - [Event-driven vs CPU-driven scaling?](#q-what-is-event-driven-vs-cpu-driven-scaling)
  - [What is Dapr?](#q-what-is-dapr-and-why-is-it-a-benefit)
  - [Why Python + FastAPI?](#q-why-python--fastapi-instead-of-nodejs-go-or-net)
  - [How to scale Python to 100k req/min?](#q-how-would-you-scale-python-to-100k-reqmin-without-rewriting-to-go)
  - [What does asynchronous mean?](#q-what-does-asynchronous-mean)
  - [What is type safety?](#q-what-is-type-safety-and-how-does-this-project-use-it)
  - [Why python:3.13-slim?](#q-why-python313-slim-instead-of-alpine-or-distroless)
  - [Why Terraform over Bicep?](#q-why-terraform-over-bicep)
- [Section 3: Security Deep Dive](#section-3-security-deep-dive)
  - [Security Architecture](#q-walk-me-through-your-security-architecture)
  - [Threat Model](#q-explain-your-threat-model)
  - [Managed Identity](#q-why-managed-identity-over-service-principal-with-secrets)
- [Section 4: Resilience Patterns](#section-4-resilience-patterns)
  - [Resilience Implementation](#q-how-did-you-implement-resilience-for-the-riskshield-api-calls)
  - [Correlation IDs](#q-explain-your-correlation-id-implementation)
- [Section 5: CI/CD Pipeline](#section-5-cicd-pipeline)
  - [Pipeline Structure](#q-walk-me-through-your-pipeline-structure)
  - [Secrets Handling](#q-how-do-you-handle-secrets-in-cicd)
- [Section 6: Trade-offs & What-Ifs](#section-6-trade-offs--what-ifs)
  - [Scaling to 100x Traffic](#q-what-would-you-change-if-this-needed-to-handle-100x-traffic)
  - [RiskShield Downtime](#q-what-if-riskshield-api-is-down-frequently)
  - [Bonus Security Features](#q-why-not-implement-all-the-bonus-security-features-by-default)
- [Section 7: Code Quality & Testing](#section-7-code-quality--testing)
- [Section 8: Questions to Ask the Interviewer](#section-8-questions-to-ask-the-interviewer)
- [Key Numbers to Remember](#key-numbers-to-remember)
- [Quick Fire Responses](#quick-fire-responses)
- [Section 9: Improvement Roadmap](#section-9-improvement-roadmap)
  - [Already Well-Implemented](#already-well-implemented-not-improvements)
  - [High Priority Improvements](#high-priority-would-do-first)
  - [Terraform Orchestration (Terramate)](#q-what-about-terraform-orchestration-at-scale)

---

## Quick Reference

| Category      | Choice                         | Key Rationale                                          |
| ------------- | ------------------------------ | ------------------------------------------------------ |
| **Compute**   | Azure Container Apps           | Scale-to-zero saves 50-70% cost in dev                 |
| **Runtime**   | Python 3.13 + FastAPI          | Fastest development, auto OpenAPI, Pydantic validation |
| **Container** | python:3.13-slim (multi-stage) | glibc compatibility, 175MB image, debugging capability |
| **Secrets**   | Key Vault + Managed Identity   | Zero secrets in code, SOC 2 compliant                  |
| **IaC**       | Terraform modules              | Reusable across environments, remote state             |
| **CI/CD**     | Azure DevOps YAML              | 3-stage pipeline, environment-based approvals          |

---

## Section 1: Project Overview

### Business Context

**FinSure Capital** is a FinTech company providing SME lending solutions. They needed to integrate with **RiskShield API** (third-party vendor) to validate loan applicants' identity and get a risk score before approving loans.

**My Role:** Design, build, containerize, and deploy a **production-ready** integration platform on Azure.

### Key Requirement: Production-Ready

The assessment explicitly required a **production-ready** solution (not a prototype). This means:

| Requirement            | What I Delivered                                         |
| ---------------------- | -------------------------------------------------------- |
| **Resilience**         | Circuit breaker, retry logic, timeouts                   |
| **Security**           | Managed Identity, Key Vault, HTTPS-only                  |
| **Observability**      | Structured logging, correlation IDs, App Insights        |
| **IaC**                | Modular Terraform, remote state, reusable for dev/prod   |
| **CI/CD**              | 3-stage pipeline, environment gating, smoke tests        |
| **Container Security** | Non-root user, multi-stage build, vulnerability scanning |

### Problem Statement

- Accept POST request with applicant details
- Call RiskShield REST API with API key authentication
- Return vendor's risk score response
- Deploy to Azure using Terraform + Azure DevOps
- **Production-ready** with DevOps and security best practices

---

## Section 2: Architecture Decisions

### Q: Why Azure Container Apps over App Service or AKS?

**Answer:**

| Criteria     | Container Apps            | App Service            | AKS          |
| ------------ | ------------------------- | ---------------------- | ------------ |
| Cost (Dev)   | ~$0/month (scale-to-zero) | ~$12/month (always-on) | ~$150/month  |
| Cost (Prod)  | ~$72/month                | ~$113/month            | ~$500/month  |
| Ops Overhead | Low                       | Low                    | High         |
| KEDA Scaling | Native                    | No                     | Manual setup |
| Dapr Ready   | Yes                       | No                     | Yes          |

**Key Reasoning:**

1. **Event-Driven Scaling (KEDA)**: Scales on HTTP requests, queue depth - not just CPU/memory. Better for bursty loan validation traffic.
2. **Dapr Integration**: Service mesh patterns (retries, circuit breakers) without code changes.
3. **Right-Sized Complexity**: Production-grade K8s without AKS cluster management overhead.
4. **Cost Efficiency**: Scale-to-zero for dev, `min_replicas=2` for prod HA.

**Trade-off:** Cold start 2-3s for dev. Production is always warm.

#### Deep Dive: Container Apps vs App Service

**When to Choose Container Apps:**
- Variable/bursty traffic, event-driven workloads
- Microservices architecture (Dapr)
- Need gRPC or TCP ingress

**When to Choose App Service:**
- Traditional web apps with steady traffic
- Need zero cold start, team unfamiliar with containers

**Cold Start Follow-up:** "Cold starts are 2-3 seconds, acceptable for loan validation (not real-time user-facing). Production uses `min_replicas=2` - no cold start."

#### Q: What is event-driven vs CPU-driven scaling?

**The Difference:**

|                 | **CPU-Driven**                 | **Event-Driven (KEDA)**                  |
| --------------- | ------------------------------ | ---------------------------------------- |
| **Triggers on** | CPU usage > 70%                | External events (requests, queues, time) |
| **Good for**    | Compute-heavy workloads        | I/O-heavy, bursty traffic                |
| **Example**     | Video processing, ML inference | APIs, queue consumers, scheduled jobs    |

**When to Choose:**
- **CPU-Driven**: Compute-intensive workloads (video encoding, ML)
- **Event-Driven**: I/O-bound APIs, bursty traffic ← **This project**

**Interview One-Liner:**

> "CPU-driven scales when compute gets busy. Event-driven scales on actual demand - requests, queue depth. For an API calling external services, event-driven responds faster."

#### Q: What is Dapr and why is it a benefit?

**Dapr = Distributed Application Runtime** - building blocks for microservices as configuration, not code.

| What Dapr Provides    | What It Means                            | Without Dapr               | With Dapr              |
| --------------------- | ---------------------------------------- | -------------------------- | ---------------------- |
| **Retries**           | Auto-retry failed API calls              | Write yourself             | Configure              |
| **Circuit Breaker**   | Stop calling failing services            | Implement yourself         | Built-in               |
| **Service Discovery** | Find services by name, not IP            | Hardcode URLs              | Automatic              |
| **State Management**  | Store data without knowing the database  | Provider-specific code     | Same API for any store |

**Why Dapr Benefits This Project:**
- Future-proof for microservices expansion
- Built into Container Apps (just enable it)

**Interview One-Liner:**

> "Dapr provides microservice building blocks - retries, circuit breakers, service discovery - as configuration instead of code. Built into Container Apps, so if we expand to multiple services, we get service mesh patterns for free."

#### When Would AKS Be the Right Choice?

**Consider AKS when:**

| Factor            | Container Apps      | AKS Needed                        |
| ----------------- | ------------------- | --------------------------------- |
| **Microservices** | < 10 services       | 10+ with complex interactions     |
| **Traffic**       | < 100k req/min      | 100k+ req/min, predictable        |
| **Team Size**     | < 5 platform eng    | 5+ with K8s expertise             |
| **Control**       | Managed abstractions| Need pod-level control, operators |

**Why AKS Was Wrong for This Project:**
1. Single service - no microservices complexity
2. No dedicated K8s expertise needed
3. Ops burden: cluster upgrades, node patching
4. Cost: ~$150/month vs ~$8/month for dev

**Interview Response:**

> "AKS for 10+ microservices with complex service mesh needs. For a single integration service, Container Apps gives 80% of K8s benefits with 20% of the complexity."

---

### Q: Why Python + FastAPI instead of Node.js, Go, or .NET?

**Answer:**

| Criterion       | Python/FastAPI  | Node.js   | Go        | .NET      |
| --------------- | --------------- | --------- | --------- | --------- |
| Dev Speed       | Fastest         | Fast      | Medium    | Medium    |
| Type Safety     | Good (Pydantic) | Moderate  | Excellent | Excellent |
| Async I/O       | Good            | Excellent | Excellent | Excellent |
| Azure SDK       | Good            | Excellent | Good      | Excellent |
| Data Validation | Best (Pydantic) | Manual    | Manual    | Good      |

**Key Reasoning:**

1. **Dev Velocity**: FastAPI auto-generates OpenAPI docs, Pydantic provides runtime validation.
2. **FinTech Standard**: Python is industry standard for financial data - easier hiring, more libraries.
3. **Python 3.13**: 16 months of production hardening, experimental JIT (10-30% faster).
4. **uv Package Manager**: 10-100x faster than pip, Rust-based.

**Trade-off:** Go would be faster for high-throughput, but Python handles 1000 req/min easily.

#### Q: How would you scale Python to 100k req/min without rewriting to Go?

**The Math:** 1 replica = ~1,000 req/min → Target 100k req/min = 100 replicas

**Strategy 1: Horizontal Scaling**

```hcl
min_replicas = 20   # Was 2
max_replicas = 100  # Was 10
```
**Cost:** ~$720/month vs ~$72/month

**Strategy 2: Add Caching (Biggest Impact)**

```python
async def get_risk_score(request: ValidateRequest) -> RiskScore:
    cache_key = f"risk:{request.idNumber}"
    cached = await redis.get(cache_key)
    if cached:
        return cached  # Cache HIT
    result = await riskshield_client.validate(request)
    await redis.setex(cache_key, 3600, result)  # Cache 1 hour
    return result
```

**Impact if 80% cache hits:** 100k req/min → 20k actual API calls → 20 replicas → **$144/month vs $720/month**

**Already Optimized:** Connection pooling (httpx AsyncClient), Async I/O (FastAPI), Non-blocking

**Interview One-Liner:**

> "Before rewriting to Go, add Redis caching. With 80% cache hits, Python handles 100k req/min with 20 replicas at a fraction of the rewrite cost."

#### Q: What does "asynchronous" mean?

> **Sync** = Do one thing at a time, wait for each to finish
> **Async** = Start multiple things, handle them as they complete

**Analogy:**
```
SYNC (like a queue): Order → Wait → Get. Total: 3 min
ASYNC (like a buzzer): Order → Get buzzer → Do other things → Pick up. Total: 2 min (parallel)
```

**In Code:**
```python
# SYNC - one at a time
result1 = call_riskshield(request1)  # Wait 2s...
result2 = call_riskshield(request2)  # Wait 2s...
# Total: 4 seconds

# ASYNC - all at once
result1, result2 = await asyncio.gather(
    call_riskshield(request1),
    call_riskshield(request2),
)
# Total: 2 seconds (parallel)
```

**Interview One-Liner:**

> "Async means the server handles multiple requests at once. FastAPI doesn't block while waiting for RiskShield - it processes other requests. That's why Python handles 1000+ req/min despite being 'slower' than Go."

### Q: What is type safety and how does this project use it?

**Simple Definition:**

> If a function expects a `str`, you MUST pass a `str`. Anything else is an error.

```python
def greet(name: str) -> str:
    return f"Hello, {name}"

greet("Jane")    # ✅ String → works
greet(123)       # ❌ Integer → type error
```

**Type Safety vs Input Validation:**

| Concept              | Catches         | Example                         |
| -------------------- | --------------- | ------------------------------- |
| **Type Safety**      | Wrong data TYPE | Pass `123` where `str` expected |
| **Input Validation** | Invalid VALUE   | User types `"abc"` for email    |

**How This Project Uses It:**

| Tool         | What It Does              | Catches                             |
| ------------ | ------------------------- | ----------------------------------- |
| **mypy**     | Checks type hints in code | Developer passes wrong type         |
| **Pydantic** | Validates at API boundary | Both wrong types AND invalid values |

**Interview One-Liner:**

> "Type safety means if a function expects a string, you must pass a string. Python is dynamically typed, so I added mypy to catch type mismatches in CI, and Pydantic to validate both types and values at the API boundary."

---

### Q: Why python:3.13-slim instead of Alpine or Distroless?

| Image                | Size  | Packages Work? | Can Debug?  |
| -------------------- | ----- | -------------- | ----------- |
| **python:3.13-slim** | 175MB | ✅ Yes         | ✅ Yes      |
| Alpine               | 100MB | ❌ Some don't  | ✅ Yes      |
| Distroless           | 90MB  | ✅ Yes         | ❌ No shell |

**Why NOT Alpine:** Uses musl libc - many Python packages must compile from source (slow builds)

**Why NOT Distroless:** No shell = can't debug production issues at 2am

**Interview One-Liner:**

> "Alpine breaks some Python packages. Distroless has no shell. Slim gives us compatibility and debugging while hitting our 200MB target."

### Q: Why Terraform over Bicep?

| Criterion         | Terraform | Bicep      |
| ----------------- | --------- | ---------- |
| Multi-cloud       | Yes       | Azure only |
| Module Ecosystem  | Massive   | Growing    |
| State Management  | Built-in  | Built-in   |

**Key Reasoning:**
1. **Multi-cloud Optionality**: Skills transfer if FinSure expands to AWS/GCP
2. **Module Library**: Huge ecosystem of pre-built modules
3. **State Management**: Remote state with locking prevents team conflicts

**Trade-off:** Bicep has better Azure IntelliSense, but vendor lock-in is a concern.

---

## Section 3: Security Deep Dive

### Q: Walk me through your security architecture.

**Defense in Depth Layers:**

```
Layer 1: Network Security
├── HTTPS only (TLS 1.2+)
└── Container Apps ingress

Layer 2: Identity & Access
├── System-Assigned Managed Identity
└── RBAC: Key Vault Secrets User, AcrPull

Layer 3: Secrets Management
├── API key in Key Vault (never in env vars)
└── Managed Identity retrieves at runtime

Layer 4: Container Security
├── Non-root user (UID 1000)
├── Multi-stage build
└── Trivy vulnerability scanning

Layer 5: Observability
├── All Key Vault access logged
└── Correlation IDs for distributed tracing
```

### Q: Explain your threat model.

**STRIDE Analysis:**

| Threat              | Mitigation                              |
| ------------------- | --------------------------------------- |
| **Spoofing**        | Azure AD auth (bonus feature - opt-in)  |
| **Tampering**       | HTTPS/TLS 1.2+ enforced                 |
| **Repudiation**     | Full audit logging in Log Analytics     |
| **Info Disclosure** | Key Vault + Managed Identity            |
| **DoS**             | Container Apps autoscaling              |
| **Elevation**       | Non-root user, RBAC, least privilege    |

**Trust Boundaries:**
1. **Internet → Azure**: Untrusted, TLS required, input validation
2. **Container App → Key Vault**: Managed Identity auth, RBAC-scoped
3. **Container App → RiskShield**: API key from Key Vault, HTTPS, timeouts

---

### Q: Why Managed Identity over Service Principal with secrets?

| Aspect    | Managed Identity       | Service Principal          |
| --------- | ---------------------- | -------------------------- |
| Secrets   | Zero                   | Must rotate manually       |
| Rotation  | Automatic (1hr tokens) | Manual process             |
| Audit     | Full Azure AD logging  | Limited                    |

**Service Principal Problems:** Secrets in CI/CD = attack surface, manual 90-day rotation, credential sprawl

**Managed Identity Benefits:** Azure handles tokens, no secrets anywhere, SOC 2 compliant

---

## Section 4: Resilience Patterns

### Q: How did you implement resilience for the RiskShield API calls?

**Three-Layer Resilience:**

**Layer 1: Timeouts**

```python
HTTP_TIMEOUT = httpx.Timeout(connect=5.0, read=10.0, write=5.0, pool=5.0)
```

**Layer 2: Retry with Exponential Backoff**

```python
@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=1, max=10),
    retry=retry_if_exception_type(httpx.HTTPStatusError),
)
```
- Retries on 5xx errors and 429 rate limiting, NOT 4xx client errors
- Wait times: 1s → 2s → 4s

**Layer 3: Circuit Breaker**

- Trips after 5 consecutive failures, rejects for 60s (fail fast)
- Protects RiskShield from thundering herd

**Why all three?** Timeouts prevent hanging, retries handle transient failures, circuit breaker prevents cascading failures.

---

### Q: Explain your correlation ID implementation.

```python
class CorrelationIDMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        correlation_id = request.headers.get("X-Correlation-ID", str(uuid.uuid4()))
        structlog.contextvars.bind_contextvars(correlation_id=correlation_id)
        response = await call_next(request)
        response.headers["X-Correlation-ID"] = correlation_id
        return response
```

**Flow:** Client → Middleware generates/propagates ID → Bound to all logs → Returned to client for support tickets

**Example Log:**
```json
{"event": "validation_completed", "correlation_id": "abc-123", "risk_score": 72, "duration_ms": 234}
```

---

## Section 5: CI/CD Pipeline

### Q: Walk me through your pipeline structure.

**3-Stage Pipeline:**

```
BUILD → INFRASTRUCTURE → DEPLOY
  │           │              │
  ▼           ▼              ▼
• Lint      • TF init     • Update Container
• Type      • TF plan     • Wait 30s
• Tests     • TF apply    • Smoke test
• Build     • (manual     • Rollback
• Trivy      for prod)
• Push ACR
```

**Stage 1: Build:** Quality gates (lint, type check, unit tests), Docker build, Trivy scan, push to ACR

**Stage 2: Infrastructure:** Dev auto-deploys, Prod requires manual approval

**Stage 3: Deploy:** Update Container App, smoke test `/health`, rollback on failure

**Environment Strategy:** `dev` branch → auto, `main` branch → manual approval

---

### Q: How do you handle secrets in CI/CD?

**Three-Tier Approach:**

**Tier 1: Variable Groups** - `finrisk-dev-secrets`, `finrisk-prod-secrets` (encrypted, masked in logs)

**Tier 2: Terraform Sensitive Variables**

```hcl
variable "riskshield_api_key" {
  type      = string
  sensitive = true  # Hidden from plan output
}
```

**Tier 3: Injected at Runtime**

```yaml
terraform apply -var="riskshield_api_key=$(RISKSHIELD_API_KEY)"
```

**Key Principle:** Secrets never in Git, Terraform state (marked sensitive), pipeline logs (masked), or env vars (retrieved from Key Vault at runtime).

---

## Section 6: Trade-offs & What-Ifs

### Q: What would you change if this needed to handle 100x traffic?

1. **Compute**: min_replicas=5, max_replicas=50
2. **Caching**: Redis for repeated applicant checks
3. **Database**: Cosmos DB for audit records at scale
4. **API Gateway**: Azure APIM for rate limiting, caching
5. **Regional**: Multi-region with Front Door
6. **Async**: Message queue for high-volume periods

**Cost impact:** ~$500-1000/month vs current ~$122/month

---

### Q: What if RiskShield API is down frequently?

**Current mitigations:**
1. Circuit breaker prevents cascading failures
2. Retry logic handles transient issues
3. 503 response with correlation ID for support

**Additional options:**
1. **Fallback**: Return cached/default risk score
2. **Queue-based**: Accept request, process later
3. **Multi-vendor**: Backup risk scoring provider
4. **SLA monitoring**: Alert on RiskShield availability

---

### Q: Why not implement all the bonus security features by default?

| Feature           | Cost Impact | When to Enable             |
| ----------------- | ----------- | -------------------------- |
| IP Restrictions   | $0          | Production with known IPs  |
| Azure AD Auth     | $0          | Production, sensitive data |
| Private Endpoints | +$35/mo     | Regulated industries       |

**Opt-In via Variables:**

```hcl
variable "enable_private_endpoints" { default = false }
variable "aad_client_id" { default = null }
```

**Reasoning:** Dev doesn't need full hardening, private endpoints require VNet-connected build agents, security is a spectrum.

---

## Section 7: Code Quality & Testing

### Q: How did you ensure code quality?

**Four-Layer Approach:**

**Layer 1: Static Analysis** - Ruff (linting), mypy --strict (type checking), fail CI on errors

**Layer 2: Unit Testing** - pytest with async support, 80%+ coverage, fixtures for Key Vault/RiskShield mocking

**Layer 3: Integration Testing** - httpx AsyncClient for API testing, all error scenarios

**Layer 4: Security Scanning** - Trivy (container), Bandit (Python), fail on HIGH/CRITICAL

---

## Section 8: Questions to Ask the Interviewer

1. "What's the current incident response process - would this integrate with PagerDuty workflows?"
2. "Are there existing Azure policies for container registries or networking?"
3. "What's the team's Terraform experience - need training documentation?"
4. "Is multi-region deployment a near-term requirement?"
5. "What's the expected traffic pattern - steady vs bursty?"

---

## Key Numbers to Remember

| Metric                    | Value      | Context                     |
| ------------------------- | ---------- | --------------------------- |
| Dev monthly cost          | ~$8        | Scale-to-zero enabled       |
| Prod monthly cost         | ~$122      | 2 replicas, always-on       |
| Container image size      | 175MB      | Under 200MB target          |
| Cold start latency        | 2-3s       | Mitigated by min_replicas=2 |
| Circuit breaker threshold | 5 failures | Then 60s recovery           |
| Retry attempts            | 3          | Exponential backoff         |
| API timeout               | 10s read   | 5s connect                  |
| Test coverage target      | 80%        | Enforced in CI              |

---

## Quick Fire Responses

**"Why Container Apps?"** → Scale-to-zero saves 70% dev costs, KEDA for event-driven scaling, Dapr-ready.

**"Why not AKS?"** → Overkill for single service, adds ops burden, $500+/month vs $72.

**"Why Python?"** → Fastest dev velocity, Pydantic validation, FinTech standard, handles 1000 req/min easily.

**"Why Key Vault?"** → Zero secrets in code, SOC 2 compliant, automatic audit logging.

**"Why Terraform?"** → Multi-cloud optionality, huge module ecosystem, built-in state management.

**"Circuit breaker pattern?"** → Fail fast after 5 failures, protects downstream, 60s recovery window.

**"Correlation IDs?"** → Distributed tracing, links all logs for a request, returned to client for support.

---

## Section 9: Improvement Roadmap

### Q: How would you improve this solution if you had more time?

> **Note:** Roadmap based on actual codebase analysis. Intentional trade-offs given 6-10 hour timebox.

---

### Already Well-Implemented (Not Improvements)

| Feature            | Implementation                  | Location                            |
| ------------------ | ------------------------------- | ----------------------------------- |
| Circuit Breaker    | 5 failures → 60s recovery       | `services/riskshield.py`            |
| Retry Logic        | 3 attempts, exponential backoff | `services/riskshield.py`            |
| Timeouts           | 5s connect, 10s read            | `services/riskshield.py`            |
| Correlation IDs    | Full middleware implementation  | `core/middleware.py`                |
| Structured Logging | structlog with JSON renderer    | `core/logging.py`                   |
| Input Validation   | Pydantic with field validators  | `models/validation.py`              |
| Secret Caching     | 5-minute TTL for Key Vault      | `core/secrets.py`                   |
| Non-root Container | appuser (UID 1000)              | `Dockerfile`                        |

---

### High Priority (Would Do First)

#### 1. Add Azure Monitor Alerts

**Current State:** Logs go to Log Analytics, but NO alert rules defined in Terraform.

**Solution:**

```hcl
resource "azurerm_monitor_metric_alert" "error_rate" {
  name                = "alert-error-rate"
  scopes              = [azurerm_container_app.main.id]
  criteria {
    metric_name      = "Requests"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 5
  }
  action {
    action_group_id = azurerm_monitor_action_group.pagerduty.id
  }
}
```

**Recommended Alerts:** 5xx > 5% (Critical), Circuit breaker open (Critical), P95 latency > 2s (Warning), Key Vault 403 (Critical)

---

#### 2. Enforce Quality Gates in CI/CD

**Current State:** All security scans have `continueOnError: true` - don't block deployment.

**Solution:** Remove `continueOnError` for critical checks

```yaml
- script: uv run ruff check src/
  continueOnError: false # Now blocks deployment

- script: uv run pytest --cov=src --cov-fail-under=80
  continueOnError: false # Enforce 80% coverage
```

---

#### 3. Add API Rate Limiting

**Current State:** No rate limiting - single client could overwhelm service or exhaust RiskShield quota.

**Solution:** Add Redis-backed rate limiting

```python
from fastapi_limiter import FastAPILimiter
from fastapi_limiter.depends import RateLimiter

@app.post("/validate",
    dependencies=[Depends(RateLimiter(times=100, seconds=60))])
async def validate(request: ValidateRequest):
    ...
```

**Terraform:** Azure Cache for Redis (~$15/mo Basic tier)

---

### Medium Priority (Would Do Next)

#### 4. Improve Graceful Degradation

**Current State:** Circuit breaker opens → returns 503 (service unavailable).

**Solution:** Return last-known response with degradation flag

```python
class ValidationResponse(BaseModel):
    riskScore: int
    riskLevel: RiskLevel
    degradedMode: bool = False
    correlationId: str
```

**Business Value:** Loan applications proceed with manual review instead of being blocked.

---

#### 5. Add Idempotency Key Support

**Current State:** No idempotency - client retries = duplicate RiskShield API calls.

**Solution:**

```python
@router.post("/validate")
async def validate(
    request: ValidateRequest,
    idempotency_key: str = Header(None, alias="Idempotency-Key")
):
    if idempotency_key:
        cached = await redis.get(f"idempotent:{idempotency_key}")
        if cached:
            return cached
    # ... process ...
    await redis.set(f"idempotent:{idempotency_key}", response, ex=3600)
```

**Why:** Safe client retries, reduces duplicate API calls, saves money.

---

#### 6. Integrate Application Insights SDK

**Current State:** Resource exists, connection string passed, but SDK NOT initialized in code.

**Solution:**

```python
from opencensus.ext.azure.trace_exporter import AzureExporter
from opencensus.trace.tracer import Tracer

exporter = AzureExporter(connection_string=os.environ["APPLICATIONINSIGHTS_CONNECTION_STRING"])
tracer = Tracer(exporter=exporter)
```

**Why:** End-to-end request tracing client → container app → RiskShield.

---

### Lower Priority (Nice to Have)

#### 7. Add Contract Tests for RiskShield API

**Current State:** 40+ tests all mock RiskShield response. No contract tests.

**Solution:** Pact contract tests

```python
from pact import Consumer, Provider

pact = Consumer('FinRisk').has_pact_with(Provider('RiskShield'))

@pact.given('valid applicant')
def test_riskshield_contract():
    (pact
     .upon_receiving('validation request')
     .with_request('POST', '/v1/score')
     .will_respond_with(200, body={'riskScore': 72, 'riskLevel': 'MEDIUM'}))
```

---

#### 8. Add SA ID Number Luhn Validation

**Current State:** Pydantic validates 13 digits, but not Luhn checksum. `0000000000000` passes.

**Solution:**

```python
@field_validator('idNumber')
@classmethod
def validate_sa_id(cls, v: str) -> str:
    if len(v) != 13 or not v.isdigit():
        raise ValueError('Must be 13 digits')
    total = 0
    for i, digit in enumerate(v[:-1]):
        d = int(digit)
        if i % 2 == 1:
            d *= 2
            if d > 9: d -= 9
        total += d
    if (10 - (total % 10)) % 10 != int(v[-1]):
        raise ValueError('Invalid SA ID (Luhn check failed)')
    return v
```

---

#### 9. Feature Flags for Safe Rollouts

**Current State:** No feature flag system.

**Solution:** Azure App Configuration with Feature Flag provider

```python
if feature_manager.is_enabled('new_scoring_algorithm'):
    return await new_algorithm(request)
return await current_algorithm(request)
```

---

### Infrastructure Improvements

| Improvement           | Current            | Proposed         | Cost      |
| --------------------- | ------------------ | ---------------- | --------- |
| Multi-region          | Single (East US 2) | Active-passive   | +$120/mo  |
| WAF                   | None               | Azure Front Door | +$35/mo   |
| Secrets auto-rotation | Manual             | 90-day policy    | $0        |
| Private endpoints     | Opt-in (var)       | Default for prod | +$35/mo   |
| Redis cache           | None               | Basic tier       | +$15/mo   |

---

### Summary: What I'd Pitch to Stakeholders

**30-Day Quick Wins:**

| Item                     | Effort  | Impact                       |
| ------------------------ | ------- | ---------------------------- |
| Add Azure Monitor alerts | 1 day   | Proactive incident response  |
| Enforce CI quality gates | 2 hours | Prevent security regressions |
| Add rate limiting        | 1 day   | Protect against abuse        |

**90-Day Improvements:**

| Item                     | Effort | Impact              |
| ------------------------ | ------ | ------------------- |
| Graceful degradation     | 3 days | Business continuity |
| Idempotency keys         | 2 days | Safe client retries |
| Application Insights SDK | 2 days | End-to-end tracing  |

**6-Month Strategic:**

| Item                    | Effort  | Impact              |
| ----------------------- | ------- | ------------------- |
| Multi-region DR         | 2 weeks | 99.99% SLA          |
| Contract testing        | 1 week  | Catch API changes   |
| Feature flags           | 1 week  | Safe rollouts       |

---

### Q: What about Terraform orchestration at scale?

**Current State:** Manual pipeline, separate dev/prod stages, no change detection

**Problem at Scale:** 10+ environments = 10+ pipeline stages, full plan on every PR, no dependency ordering

#### Option 1: Terramate

**What it provides:** Code generation, change detection, stack orchestration, GitOps native

**Key commands:**

```bash
# Only runs stacks with changes since main
terramate run --changed -- terraform plan
# Run stacks in dependency order
terramate run -- terraform apply
```

**Why Terramate:** Lightweight, no infra, works with any CI. Newer but growing.

**When I'd recommend:** 3+ environments OR multi-region OR team of 3+ platform engineers

#### Option 2: Keep Current Approach (Recommended for Now)

**Why:** Only 2 environments, simple dependency graph, pipeline is ~100 lines

**Incremental improvement:**

```yaml
- script: |
    CHANGED=$(git diff --name-only HEAD~1 HEAD -- terraform/)
    if [ -n "$CHANGED" ]; then
      terraform plan
    else
      echo "No terraform changes, skipping"
    fi
```

---

### How to Frame This in Interview

**Don't say:** "I made mistakes, here's what I'd fix"

**Do say:** "Given the 6-10 hour timebox, I focused on production-ready fundamentals - circuit breaker, retries, managed identity, structured logging. Here's my prioritized v2 backlog based on actual gaps."

**What I intentionally deferred:** Alerts (needs PagerDuty context), rate limiting (Redis decision), contract testing (RiskShield API access)

**Key insight:** Solution is production-ready for controlled rollout. Improvements are about operational maturity, not missing fundamentals.

---

_Document Version: 1.1_
_Created: 2026-02-24_
_For: Pollinate Platform Engineering Interview_
