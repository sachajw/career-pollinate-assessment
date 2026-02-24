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

| Requirement | What I Delivered |
|-------------|------------------|
| **Resilience** | Circuit breaker, retry logic, timeouts |
| **Security** | Managed Identity, Key Vault, HTTPS-only |
| **Observability** | Structured logging, correlation IDs, App Insights |
| **IaC** | Modular Terraform, remote state, reusable for dev/prod |
| **CI/CD** | 3-stage pipeline, environment gating, smoke tests |
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

**Key Reasoning (Production-Ready Focus):**

1. **Event-Driven Scaling (KEDA)**: Production traffic is bursty. KEDA scales on HTTP requests, queue depth, cron schedules - not just CPU/memory. This is more efficient for a loan validation API.
2. **Production Resilience**: Dapr integration provides service mesh patterns (retries, circuit breakers) without code changes. Future-proof for microservices expansion.
3. **Right-Sized Complexity**: AKS is overkill for a single service - adds cluster management, node patching, upgrade cycles. Container Apps gives production-grade K8s without the ops burden.
4. **Cost Efficiency**: Scale-to-zero saves dev costs, but production uses `min_replicas=2` for high availability.

**Trade-off Accepted:** Cold start latency of 2-3s for dev environment. Production mitigates this with `min_replicas=2` (always warm).

**If asked about App Service:** App Service is production-ready, but lacks event-driven scaling (KEDA) and Dapr. For a FinTech integration that may have bursty loan application periods, Container Apps scales more intelligently.

#### Deep Dive: Container Apps vs App Service

**Pricing Philosophy:**

```
Container Apps:  Pay for what you USE (vCPU-seconds)
App Service:     Pay for what you RESERVE (instance-hours)
```

**Scaling Model:**

```
Container Apps:  0 → 300 replicas (KEDA-driven)
                 Scales on: HTTP requests, queue depth, cron schedules, custom metrics

App Service:     1 → 100 instances (Premium v3, CPU/memory-driven)
                 Scales on: CPU > 70%, memory > 70%, HTTP queue length
```

**When to Choose Container Apps:**

- Variable/unpredictable traffic (scale-to-zero saves money)
- Event-driven workloads (queue processing, scheduled jobs)
- Microservices architecture (Dapr service mesh)
- Need gRPC or TCP ingress
- Burst traffic patterns

**When to Choose App Service:**

- Traditional web apps (.NET, Node.js, Python, Java)
- Predictable, steady traffic
- Need zero cold start (always warm)
- Team unfamiliar with containers
- Simple web app + API use case

**Cold Start Follow-up:**

> "Cold starts are 2-3 seconds, acceptable for a loan validation API that's not real-time user-facing. In production with `min_replicas=2`, there's no cold start - you just lose scale-to-zero cost savings."

#### Q: What is event-driven vs CPU-driven scaling?

**The Difference:**

| | **CPU-Driven** | **Event-Driven (KEDA)** |
|---|----------------|-------------------------|
| **Triggers on** | CPU usage > 70% | External events (requests, queues, time) |
| **Good for** | Compute-heavy workloads | I/O-heavy, bursty traffic |
| **Example** | Video processing, ML inference | APIs, queue consumers, scheduled jobs |

**Visual:**
```
CPU-DRIVEN:
Request burst → Wait for CPU to hit 70% → Then scale up

EVENT-DRIVEN:
Request burst → 100 requests in queue → Scale up immediately
```

**When to Choose CPU-Driven:**
- Compute-intensive (video encoding, ML training)
- Steady, predictable traffic

**When to Choose Event-Driven:**
- I/O-bound (APIs calling external services) ← **This project**
- Bursty, unpredictable traffic
- Queue-based processing

**Interview One-Liner:**
> "CPU-driven scales when compute gets busy. Event-driven scales on actual demand - requests, queue depth. For an API calling external services, event-driven responds faster because it doesn't wait for CPU to rise."

#### Q: What is Dapr and why is it a benefit?

**Dapr = Distributed Application Runtime**

Building blocks for microservices that handle cross-cutting concerns WITHOUT writing the code.

| What Dapr Provides | Without Dapr | With Dapr |
|--------------------|--------------|-----------|
| **Retries** | Write retry logic yourself | Configure, don't code |
| **Circuit Breaker** | Implement yourself | Built-in |
| **Service Discovery** | Hardcode URLs | Automatic |
| **State Management** | Write Redis/SQL code | Same API for any store |
| **Pub/Sub** | Provider-specific code | Same API for Kafka, RabbitMQ, etc. |

**Example:**
```python
# WITHOUT Dapr - write retry logic
@retry(stop=stop_after_attempt(3))
async def call_riskshield(request):
    return await http_client.post(url, json=request)

# WITH Dapr - just configure, Dapr handles retry
async def call_riskshield(request):
    return await dapr_client.invoke_method("riskshield", "score", data=request)
```

**Why Dapr Benefits This Project:**
- **Future-proof** - Add microservices without rewriting infrastructure code
- **Less code** - Retries, circuit breakers handled by Dapr
- **Built into Container Apps** - Just enable it, no extra deployment

**Interview One-Liner:**
> "Dapr provides microservice building blocks - retries, circuit breakers, service discovery - as configuration instead of code. It's built into Container Apps, so if we expand to multiple services, we get service mesh patterns without writing infrastructure code."

#### When Would AKS Be the Right Choice?

**AKS Thresholds - consider AKS when:**

| Factor            | Container Apps Limit      | AKS Needed                                          |
| ----------------- | ------------------------- | --------------------------------------------------- |
| **Microservices** | < 10 services             | 10+ services with complex interactions              |
| **Traffic**       | < 100k req/min            | 100k+ req/min, predictable baseline                 |
| **Team Size**     | < 5 platform engineers    | 5+ with K8s expertise                               |
| **Control**       | Managed abstractions      | Need pod-level control, custom operators            |
| **Network**       | Basic ingress             | Service mesh (Istio), complex policies              |
| **Compliance**    | Standard Azure compliance | Custom security policies, Azure Policy at pod level |

**Cost Crossover Point:**

```
Container Apps:  $0.000024/vCPU-s + $0.000003/GiB-s
AKS (D2s v3):    ~$70/node/month + control plane (free)

Crossover: ~50-100k sustained req/min
- Below: Container Apps cheaper
- Above: AKS with reserved instances cheaper
```

**What AKS Provides That Container Apps Doesn't:**

| Capability               | Container Apps | AKS                           |
| ------------------------ | -------------- | ----------------------------- |
| Pod-to-pod communication | Limited (Dapr) | Full CNI, Network Policies    |
| Custom operators         | No             | Yes                           |
| DaemonSets               | No             | Yes                           |
| StatefulSets             | No             | Yes                           |
| Node pools               | No             | Yes (GPU, high-memory, spot)  |
| Init containers          | Limited        | Full support                  |
| Sidecar patterns         | Dapr sidecars  | Any sidecar                   |
| RBAC granularity         | App-level      | Pod/namespace-level           |
| Admission controllers    | No             | Yes (OPA Gatekeeper, Kyverno) |

**Why AKS Was Wrong for This Project:**

1. **Single Service** - No microservices complexity to manage
2. **Small Team** - No dedicated K8s expertise needed
3. **Ops Burden** - Cluster upgrades, node patching, CNI management
4. **Cost** - Minimum ~$150/month vs ~$8/month for dev
5. **Time to Value** - Hours to set up AKS properly vs minutes for Container Apps

**Interview Response:**

> "AKS would be the right choice if we had 10+ microservices with complex service-to-service communication, needed a service mesh like Istio, or had compliance requirements for pod-level security policies. For a single integration service, the operational overhead doesn't justify the control. Container Apps gives us 80% of K8s benefits with 20% of the complexity."

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

1. **Development Velocity**: FastAPI generates OpenAPI docs automatically, Pydantic provides runtime validation. I can ship faster with fewer bugs.
2. **FinTech Standard**: Python is the industry standard for financial data processing - easier to hire, more library support.
3. **Python 3.13 Specifically**: 16 months of production hardening, experimental JIT compiler (10-30% faster), enhanced error messages. 3.14 is too new (4 months), 3.12 lacks recent features.
4. **uv Package Manager**: 10-100x faster than pip, Rust-based, generates lock files automatically.

**Trade-off Accepted:** Go would be faster for high-throughput scenarios, but Python handles 1000 req/min easily which exceeds our requirements.

**If challenged on performance:** The assessment required 1000 req/min - Python handles this comfortably. If we needed 100k req/min, I'd choose Go. Right tool for the job.

#### Q: How would you scale Python to 100k req/min without rewriting to Go?

**The Math:**
```
Current:  1 replica = ~1,000 req/min
Target:   100,000 req/min = 100 replicas
```

**Strategy 1: Horizontal Scaling (Easiest)**
```hcl
# Just increase replicas in Terraform
min_replicas = 20   # Was 2
max_replicas = 100  # Was 10
```
**Cost:** ~$720/month vs ~$72/month

**Strategy 2: Add Caching (Biggest Impact)**

Most applicants get checked multiple times. Cache the result.
```python
async def get_risk_score(request: ValidateRequest) -> RiskScore:
    cache_key = f"risk:{request.idNumber}"
    cached = await redis.get(cache_key)

    if cached:
        return cached  # Cache HIT - instant response

    result = await riskshield_client.validate(request)
    await redis.setex(cache_key, 3600, result)  # Cache 1 hour
    return result
```

**Impact if 80% cache hits:**
- 100k req/min → 20k actual API calls
- 20 replicas instead of 100
- **$144/month instead of $720/month**

**Strategy 3: Already Optimized**

| Optimization | Status | Impact |
|--------------|--------|--------|
| Connection pooling | ✅ httpx AsyncClient | Reuses connections |
| Async I/O | ✅ FastAPI + httpx | Handles concurrency |
| Non-blocking | ✅ All I/O is async | No thread blocking |

**Recommended Approach:**
```
Step 1: Add Redis caching (1 day) → Handles 80% of traffic
Step 2: Scale to 20-30 replicas    → Handles remaining 20%
Step 3: Add Azure Front Door       → Cache at edge

Total: ~$200/mo vs $720/mo (just scaling) vs rewrite cost
```

**Interview One-Liner:**
> "Before rewriting to Go, I'd add Redis caching - most applicants get checked multiple times. With 80% cache hits, Python handles 100k req/min with 20 replicas at a fraction of the rewrite cost."

#### Q: What does "asynchronous" mean?

**Simple Definition:**
> **Sync** = Do one thing at a time, wait for each to finish
> **Async** = Start multiple things, handle them as they complete

**Real-World Analogy:**

```
SYNCHRONOUS (like a queue):
1. Order food → Wait 2 min → Get food
2. Order drink → Wait 1 min → Get drink
Total: 3 minutes

ASYNCHRONOUS (like a buzzer):
1. Order food → Get buzzer
2. Order drink → Get buzzer
3. Sit down, check phone (do other things)
4. Buzzers ring → Pick up both
Total: 2 minutes (happened in parallel)
```

**In Code:**

```python
# SYNCHRONOUS - one at a time
result1 = call_riskshield(request1)  # Wait 2 sec...
result2 = call_riskshield(request2)  # Wait 2 sec...
result3 = call_riskshield(request3)  # Wait 2 sec...
# Total: 6 seconds

# ASYNCHRONOUS - all at once
result1, result2, result3 = await asyncio.gather(
    call_riskshield(request1),  # Start
    call_riskshield(request2),  # Start
    call_riskshield(request3),  # Start
)
# Total: 2 seconds (all ran in parallel)
```

**Why It Matters for This Project:**

| Server Type | 100 Requests | Wait Time |
|-------------|--------------|-----------|
| Synchronous | One at a time | Last request waits 200s |
| Async (FastAPI) | All start immediately | All done in ~2s |

**Interview One-Liner:**
> "Asynchronous means the server handles multiple requests at once instead of waiting for each to finish. FastAPI doesn't block while waiting for RiskShield - it processes other requests. That's why Python handles 1000+ req/min despite being 'slower' than Go."

---

**Simple Definition:**
> If a function expects a `str`, you MUST pass a `str`. Anything else is an error.

```python
def greet(name: str) -> str:
    return f"Hello, {name}"

greet("Jane")    # ✅ String → works
greet(123)       # ❌ Integer → type error
greet(True)      # ❌ Boolean → type error
```

**Why It's Called "Safety":**
Without type safety, languages silently do weird things:
```python
# JavaScript (no type safety)
score = "72"
result = score + 10    // "7210" - silently concatenated strings!

# Python + mypy (type safe)
score: int = 72
result = score + "10"  # ❌ mypy error - caught before running
```

**Type Safety vs Input Validation:**

| Concept | Catches | Example |
|---------|---------|---------|
| **Type Safety** | Wrong data TYPE | Pass `123` where `str` expected |
| **Input Validation** | Invalid VALUE | User types `"abc"` for email |

```python
# Type safety - wrong TYPE
def get_risk(score: int) -> str: ...
get_risk("72")     # ❌ Passed string, expected int

# Input validation - invalid VALUE
class Request(BaseModel):
    idNumber: str = Field(..., min_length=13)
Request(idNumber="123")  # ❌ Correct type (str), but too short
```

**How This Project Uses It:**

| Tool | What It Does | Catches |
|------|--------------|---------|
| **mypy** | Checks type hints in code | Developer passes wrong type |
| **Pydantic** | Validates at API boundary | Both wrong types AND invalid values |

**Interview One-Liner:**
> "Type safety means if a function expects a string, you must pass a string. Python is dynamically typed, so I added mypy to catch type mismatches in CI, and Pydantic to validate both types and values at the API boundary."
|---------------------|------------------|
| Bugs found in production | Bugs found in IDE/CI |
| Refactoring is risky | Compiler catches breaks |
| Read code to understand | Types document intent |

**Interview Response:**
> "Python is dynamically typed, but I added static type hints with mypy for CI checks and Pydantic for runtime validation. This 'gradual typing' catches invalid API requests at the boundary and catches developer mistakes in CI - before production."

---

### Q: Why python:3.13-slim instead of Alpine or Distroless?

**Simple Rule:**
> **Alpine** = smallest but packages break
> **Distroless** = most secure but can't debug
> **Slim** = sweet spot (works + debuggable + small enough)

| Image | Size | Packages Work? | Can Debug? |
|-------|------|----------------|------------|
| **python:3.13-slim** | 175MB | ✅ Yes | ✅ Yes |
| Alpine | 100MB | ❌ Some don't | ✅ Yes |
| Distroless | 90MB | ✅ Yes | ❌ No shell |

**Why NOT Alpine:**
```bash
# Alpine uses musl libc - many Python packages don't have wheels
pip install azure-identity  # ❌ Must compile from source = slow builds

# Slim uses glibc - everything just works
pip install azure-identity  # ✅ Pre-built wheel, installs in seconds
```

**Why NOT Distroless:**
```bash
# Production incident at 2am - need to debug?
kubectl exec -it mypod -- /bin/sh
# Distroless: ❌ No shell exists
# Slim:        ✅ Works, can inspect and debug
```

**Why Slim:**
- All packages work (glibc compatibility)
- Shell access for debugging
- 175MB is under 200MB target

**Interview One-Liner:**
> "Alpine breaks some Python packages. Distroless has no shell so you can't debug production issues. Slim gives us compatibility and debugging while still hitting our size target."

### Q: Why Terraform over Bicep?

**Answer:**

| Criterion         | Terraform | Bicep      |
| ----------------- | --------- | ---------- |
| Multi-cloud       | Yes       | Azure only |
| Module Ecosystem  | Massive   | Growing    |
| State Management  | Built-in  | Built-in   |
| Azure Integration | Good      | Excellent  |
| Learning Curve    | Steeper   | Easier     |

**Key Reasoning:**

1. **Multi-cloud Optionality**: If FinSure ever expands to AWS/GCP, Terraform skills transfer directly.
2. **Module Library**: Huge ecosystem of pre-built modules - I leveraged patterns from the Terraform registry.
3. **State Management**: Remote state in Azure Storage with locking prevents team conflicts.

**Trade-off Accepted:** Bicep has better Azure-specific IntelliSense and some cleaner syntax, but vendor lock-in is a concern for platform engineers.

---

## Section 3: Security Deep Dive

### Q: Walk me through your security architecture.

**Answer - Defense in Depth Layers:**

```
Layer 1: Network Security
├── HTTPS only (TLS 1.2+)
├── Container Apps ingress
└── Rate limiting (100 req/replica)

Layer 2: Identity & Access
├── System-Assigned Managed Identity
├── RBAC: Key Vault Secrets User (least privilege)
└── RBAC: AcrPull (image pull only)

Layer 3: Secrets Management
├── API key in Key Vault (never in env vars)
├── Managed Identity retrieves at runtime
└── 90-day rotation policy

Layer 4: Container Security
├── Non-root user (UID 1000)
├── Multi-stage build (no build tools in runtime)
├── Trivy vulnerability scanning in CI/CD
└── Minimal attack surface

Layer 5: Observability
├── All Key Vault access logged
├── Structured logging with correlation IDs
└── Application Insights distributed tracing
```

### Q: Explain your threat model.

**Answer - STRIDE Analysis:**

| Threat              | Example                      | My Mitigation                              |
| ------------------- | ---------------------------- | ------------------------------------------ |
| **Spoofing**        | Attacker impersonates client | Azure AD auth (bonus feature - opt-in)     |
| **Tampering**       | Data modified in transit     | HTTPS/TLS 1.2+ enforced                    |
| **Repudiation**     | Attacker denies actions      | Full audit logging in Log Analytics        |
| **Info Disclosure** | API keys leaked              | Key Vault + Managed Identity, no env vars  |
| **DoS**             | Service overwhelmed          | Container Apps autoscaling + rate limiting |
| **Elevation**       | Container breakout           | Non-root user, RBAC, least privilege       |

**Trust Boundaries:**

1. **Internet → Azure**: Untrusted traffic, TLS required, input validation
2. **Container App → Key Vault**: Managed Identity auth, RBAC-scoped
3. **Container App → RiskShield**: API key from Key Vault, HTTPS, timeouts

---

### Q: Why Managed Identity over Service Principal with secrets?

**Answer:**

| Aspect    | Managed Identity       | Service Principal          |
| --------- | ---------------------- | -------------------------- |
| Secrets   | Zero                   | Must rotate manually       |
| Rotation  | Automatic (1hr tokens) | Manual process             |
| Audit     | Full Azure AD logging  | Limited                    |
| Explosion | No credential sprawl   | Multiple secrets to manage |

**The Problem with Service Principals:**

- Secrets in CI/CD = attack surface
- Must rotate every 90 days = operational burden
- Multiple SPs = credential sprawl
- If leaked, attacker has 90 days of access

**Managed Identity Benefits:**

- Azure handles token lifecycle
- No secrets in code, config, or CI/CD
- Automatic rotation (1 hour tokens)
- SOC 2 compliant (no password management)

---

## Section 4: Resilience Patterns

### Q: How did you implement resilience for the RiskShield API calls?

**Answer - Three-Layer Resilience:**

**Layer 1: Timeouts**

```python
HTTP_TIMEOUT = httpx.Timeout(
    connect=5.0,   # Connection timeout
    read=10.0,     # API response timeout
    write=5.0,     # Request write timeout
    pool=5.0       # Connection pool timeout
)
```

**Layer 2: Retry with Exponential Backoff**

```python
@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=1, max=10),
    retry=retry_if_exception_type(httpx.HTTPStatusError),
)
```

- Retries on 5xx server errors and 429 rate limiting
- Does NOT retry on 4xx client errors (bad request, unauthorized)
- Wait times: 1s → 2s → 4s (max 7s + original request)

**Layer 3: Circuit Breaker**

- Trips after 5 consecutive failures
- Rejects requests immediately for 60 seconds (fail fast)
- Protects RiskShield from thundering herd
- Logs when circuit opens/closes

**Why all three?**

- Timeouts prevent hanging requests
- Retries handle transient failures
- Circuit breaker prevents cascading failures

---

### Q: Explain your correlation ID implementation.

**Answer:**

```python
class CorrelationIDMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        # Use existing ID or generate new UUID v4
        correlation_id = request.headers.get("X-Correlation-ID", str(uuid.uuid4()))

        # Bind to structlog context (available in all logs)
        structlog.contextvars.bind_contextvars(correlation_id=correlation_id)

        response = await call_next(request)

        # Return to client for distributed tracing
        response.headers["X-Correlation-ID"] = correlation_id
        return response
```

**Flow:**

1. Client sends request (with or without correlation ID)
2. Middleware generates/propagates ID
3. ID bound to all structured logs via structlog
4. ID propagated to RiskShield API call
5. ID returned to client for support tickets

**Example Log:**

```json
{
  "event": "validation_completed",
  "correlation_id": "abc-123-def-456",
  "risk_score": 72,
  "duration_ms": 234
}
```

---

## Section 5: CI/CD Pipeline

### Q: Walk me through your pipeline structure.

**Answer - 3-Stage Pipeline:**

```
┌─────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   BUILD     │────▶│  INFRASTRUCTURE │────▶│     DEPLOY      │
└─────────────┘     └─────────────────┘     └─────────────────┘
      │                    │                       │
      ▼                    ▼                       ▼
 • Lint (Ruff)       • TF init              • Update Container
 • Type check        • TF plan              • Wait for rollout
 • Unit tests        • TF apply             • Smoke test
 • Docker build      • (manual for prod)    • Verify response
 • Trivy scan
 • Push to ACR
```

**Stage 1: Build (Automated)**

- Quality gates: lint, type check, unit tests
- Build Docker image with BuildId tag
- Scan with Trivy (fail on HIGH/CRITICAL)
- Push to ACR

**Stage 2: Infrastructure**

- Dev: Automatic after Build succeeds
- Prod: Manual approval required

**Stage 3: Deploy**

- Update Container App image
- Wait 30s for rollout
- Smoke test `/health` endpoint
- Rollback on failure

**Environment Strategy:**

- `dev` branch → dev environment (automatic)
- `main` branch → prod environment (manual approval)

---

### Q: How do you handle secrets in CI/CD?

**Answer - Three-Tier Approach:**

**Tier 1: Variable Groups (Azure DevOps)**

- `finrisk-dev-secrets` - dev environment secrets
- `finrisk-prod-secrets` - prod environment secrets
- Secrets are encrypted at rest, masked in logs

**Tier 2: Terraform Sensitive Variables**

```hcl
variable "riskshield_api_key" {
  type      = string
  sensitive = true  # Hidden from plan output
}
```

**Tier 3: Injected at Runtime**

```yaml
# Pipeline passes secret via -var flag
terraform apply -var="riskshield_api_key=$(RISKSHIELD_API_KEY)"
```

**Key Principle:** Secrets are never in:

- Git repository
- Terraform state file (marked sensitive)
- Pipeline logs (masked automatically)
- Environment variables (retrieved from Key Vault at runtime)

---

## Section 6: Trade-offs & What-Ifs

### Q: What would you change if this needed to handle 100x traffic?

**Answer:**

1. **Compute**: Increase min_replicas to 5, max_replicas to 50
2. **Caching**: Add Redis cache for repeated applicant checks
3. **Database**: Store audit records in Cosmos DB for scale
4. **API Gateway**: Add Azure APIM for rate limiting, caching
5. **Regional**: Deploy to multiple regions with Front Door
6. **Async**: Consider message queue for high-volume periods

**Estimated cost impact:** ~$500-1000/month vs current ~$122/month

---

### Q: What if RiskShield API is down frequently?

**Answer:**

Current mitigations:

1. Circuit breaker prevents cascading failures
2. Retry logic handles transient issues
3. 503 response with correlation ID for support

**Additional options I'd consider:**

1. **Fallback response**: Return cached/default risk score
2. **Queue-based processing**: Accept request, process later
3. **Multi-vendor**: Integrate backup risk scoring provider
4. **SLA monitoring**: Alert on RiskShield availability

---

### Q: Why not implement all the bonus security features by default?

**Answer:**

| Feature           | Cost Impact | Complexity | When to Enable             |
| ----------------- | ----------- | ---------- | -------------------------- |
| IP Restrictions   | $0          | Low        | Production with known IPs  |
| Azure AD Auth     | $0          | Medium     | Production, sensitive data |
| Private Endpoints | +$35/mo     | High       | Regulated industries       |

**My Approach - Opt-In via Variables:**

```hcl
variable "enable_private_endpoints" { default = false }
variable "aad_client_id" { default = null }
variable "kv_allowed_ips" { default = [] }
```

**Reasoning:**

- Dev environment doesn't need full security hardening
- Private endpoints require VNet-connected build agents
- Cost/benefit analysis for each environment
- Security is a spectrum, not binary

---

## Section 7: Code Quality & Testing

### Q: How did you ensure code quality?

**Answer - Four-Layer Approach:**

**Layer 1: Static Analysis**

- Ruff for linting (replaces flake8, isort, black)
- mypy --strict for type checking
- Both run in CI, fail pipeline on errors

**Layer 2: Unit Testing**

- pytest with async support
- 80%+ coverage target
- Fixtures for Key Vault, RiskShield mocking

**Layer 3: Integration Testing**

- httpx AsyncClient for API testing
- Test all error scenarios (timeout, 5xx, invalid input)

**Layer 4: Security Scanning**

- Trivy for container vulnerabilities
- Bandit for Python security issues
- Fail on HIGH/CRITICAL findings

---

## Section 8: Questions to Ask the Interviewer

**Shows engagement and depth of thinking:**

1. "What's the current incident response process - would this integrate with existing PagerDuty/ops workflows?"

2. "Are there existing Azure policies I'd need to comply with for container registries or networking?"

3. "What's the team's experience level with Terraform - should I plan for training documentation?"

4. "Is multi-region deployment a near-term requirement, or is single-region acceptable for now?"

5. "What's the expected traffic pattern - steady state vs bursty? This affects autoscaling configuration."

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

**Answer - Prioritized by Impact:**

> **Note:** This roadmap is based on actual codebase analysis. I made intentional trade-offs given the 6-10 hour timebox.

---

### Already Well-Implemented (Not Improvements)

| Feature            | Implementation                  | Location                            |
| ------------------ | ------------------------------- | ----------------------------------- |
| Circuit Breaker    | 5 failures → 60s recovery       | `services/riskshield.py`            |
| Retry Logic        | 3 attempts, exponential backoff | `services/riskshield.py` (tenacity) |
| Timeouts           | 5s connect, 10s read            | `services/riskshield.py` (httpx)    |
| Correlation IDs    | Full middleware implementation  | `core/middleware.py`                |
| Structured Logging | structlog with JSON renderer    | `core/logging.py`                   |
| Input Validation   | Pydantic with field validators  | `models/validation.py`              |
| Secret Caching     | 5-minute TTL for Key Vault      | `core/secrets.py`                   |
| Demo Mode          | Fallback when no API key        | `services/riskshield.py`            |
| Health Probes      | Liveness + readiness endpoints  | `api/v1/routes.py`                  |
| Non-root Container | appuser (UID 1000)              | `Dockerfile`                        |
| Multi-stage Build  | Builder + production stages     | `Dockerfile`                        |

---

### High Priority (Would Do First)

#### 1. Add Azure Monitor Alerts

**Current State:** Logs go to Log Analytics, but NO alert rules defined in Terraform. All monitoring is reactive (manual dashboard review).

**Gap:** No `azurerm_monitor_metric_alert` or `azurerm_monitor_activity_log_alert` resources.

**Solution:** Add Terraform alert resources

```hcl
resource "azurerm_monitor_metric_alert" "error_rate" {
  name                = "alert-error-rate"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_app.main.id]

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
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

**Recommended Alerts:**

| Alert                   | Condition                | Severity |
| ----------------------- | ------------------------ | -------- |
| High error rate         | 5xx > 5% over 5 min      | Critical |
| Circuit breaker open    | Consecutive failures > 5 | Critical |
| P95 latency             | Response time > 2s       | Warning  |
| Key Vault access denied | 403 responses            | Critical |

---

#### 2. Enforce Quality Gates in CI/CD

**Current State:** All security scans have `continueOnError: true` - they report issues but don't block deployment.

**Gap:**

```yaml
- script: uv run ruff check src/
  continueOnError: true # Doesn't fail build

- script: uv run bandit -r src/
  continueOnError: true # Doesn't fail build
```

**Solution:** Remove `continueOnError` for critical checks, or add quality thresholds

```yaml
- script: uv run ruff check src/
  continueOnError: false # Now blocks deployment

- script: uv run pytest --cov=src --cov-fail-under=80
  continueOnError: false # Enforce 80% coverage
```

**Business Case:** Prevent security issues from reaching production.

---

#### 3. Add API Rate Limiting

**Current State:** No rate limiting - a single client could overwhelm the service or exhaust RiskShield API quota.

**Gap:** No `fastapi-limiter` or similar middleware.

**Solution:** Add Redis-backed rate limiting

```python
from fastapi_limiter import FastAPILimiter
from fastapi_limiter.depends import RateLimiter

@app.post("/validate",
    dependencies=[Depends(RateLimiter(times=100, seconds=60))])
async def validate(request: ValidateRequest):
    ...
```

**Terraform Addition:** Azure Cache for Redis instance (~$15/mo for Basic).

---

### Medium Priority (Would Do Next)

#### 4. Improve Graceful Degradation

**Current State:** Demo mode exists for local development, but when circuit breaker opens in production, it returns 503 (service unavailable).

**Gap:** No stale data fallback when RiskShield is unavailable.

**Solution:** Return last-known response with degradation flag

```python
class ValidationResponse(BaseModel):
    riskScore: int
    riskLevel: RiskLevel
    degradedMode: bool = False
    correlationId: str
```

**Business Value:** Loan applications can proceed with manual review instead of being blocked.

---

#### 5. Add Idempotency Key Support

**Current State:** No idempotency - client retries result in duplicate RiskShield API calls.

**Gap:** No `Idempotency-Key` header handling.

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

**Why:** Safe retries for clients, reduces duplicate API calls, saves money.

---

#### 6. Integrate Application Insights SDK

**Current State:** Application Insights resource exists, connection string passed to container, but SDK is NOT initialized in code.

**Gap:** `opencensus-ext-azure` is in dependencies but not used. No custom metrics or distributed tracing.

**Solution:**

```python
from opencensus.ext.azure.trace_exporter import AzureExporter
from opencensus.trace.tracer import Tracer

exporter = AzureExporter(connection_string=os.environ["APPLICATIONINSIGHTS_CONNECTION_STRING"])
tracer = Tracer(exporter=exporter)

# Now get: distributed tracing, dependency tracking, custom metrics
```

**Why:** End-to-end request tracing from client → container app → RiskShield.

---

### Lower Priority (Nice to Have)

#### 7. Add Contract Tests for RiskShield API

**Current State:** 40+ unit/integration tests exist, but all mock the RiskShield response. No contract tests.

**Gap:** If RiskShield changes their API schema, we won't know until production.

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

**Current State:** Pydantic validates 13 digits, but doesn't verify Luhn checksum.

**Gap:** Invalid ID numbers like `0000000000000` pass validation.

**Solution:**

```python
@field_validator('idNumber')
@classmethod
def validate_sa_id(cls, v: str) -> str:
    if len(v) != 13 or not v.isdigit():
        raise ValueError('Must be 13 digits')

    # Luhn algorithm validation
    total = 0
    for i, digit in enumerate(v[:-1]):
        d = int(digit)
        if i % 2 == 1:
            d *= 2
            if d > 9:
                d -= 9
        total += d
    if (10 - (total % 10)) % 10 != int(v[-1]):
        raise ValueError('Invalid SA ID number (Luhn check failed)')
    return v
```

---

#### 9. Feature Flags for Safe Rollouts

**Current State:** No feature flag system.

**Solution:** Azure App Configuration with Feature Flag provider

```python
from azure.appconfiguration import AzureAppConfigurationClient

if feature_manager.is_enabled('new_scoring_algorithm'):
    return await new_algorithm(request)
return await current_algorithm(request)
```

---

### Infrastructure Improvements

| Improvement           | Current            | Proposed         | Cost Impact |
| --------------------- | ------------------ | ---------------- | ----------- |
| Multi-region          | Single (East US 2) | Active-passive   | +$120/mo    |
| WAF                   | None               | Azure Front Door | +$35/mo     |
| Secrets auto-rotation | Manual             | 90-day policy    | $0          |
| Private endpoints     | Opt-in (var)       | Default for prod | +$35/mo     |
| Redis cache           | None               | Basic tier       | +$15/mo     |

---

### Summary: What I'd Pitch to Stakeholders

**30-Day Quick Wins (Low effort, high impact):**

| Item                     | Effort  | Impact                       |
| ------------------------ | ------- | ---------------------------- |
| Add Azure Monitor alerts | 1 day   | Proactive incident response  |
| Enforce CI quality gates | 2 hours | Prevent security regressions |
| Add rate limiting        | 1 day   | Protect against abuse        |

**90-Day Improvements (Medium effort):**

| Item                     | Effort | Impact              |
| ------------------------ | ------ | ------------------- |
| Graceful degradation     | 3 days | Business continuity |
| Idempotency keys         | 2 days | Safe client retries |
| Application Insights SDK | 2 days | End-to-end tracing  |

**6-Month Strategic:**

| Item                    | Effort  | Impact                  |
| ----------------------- | ------- | ----------------------- |
| Multi-region DR         | 2 weeks | 99.99% SLA              |
| Contract testing        | 1 week  | Catch API changes early |
| Feature flags           | 1 week  | Safe rollouts           |
| Terramate orchestration | 1 week  | Scalable IaC workflow   |

---

### Q: What about Terraform orchestration at scale?

**Current State:**

- Manual pipeline with `terraform init/plan/apply` commands
- Separate pipeline stages for dev/prod
- No change detection - runs all stacks even if unchanged
- Some code duplication between `environments/dev/` and `environments/prod/`

**Problem at Scale:**

- 10+ environments = 10+ pipeline stages to maintain
- Every PR triggers full plan even for unrelated changes
- No automatic dependency ordering between stacks
- Manual state file management

#### Option 1: Terramate

**What it provides:**

- **Code generation** - DRY Terraform with templates
- **Change detection** - Only run stacks with git changes
- **Stack orchestration** - Automatic dependency ordering
- **GitOps native** - Works with any CI/CD

**Example structure:**

```
terramate/
├── config.tm.hcl          # Global config
├── stacks/
│   ├── dev/
│   │   └── stack.tm.hcl   # Dev stack config
│   └── prod/
│       └── stack.tm.hcl   # Prod stack config
└── modules/               # Generated from templates
```

**Key command:**

```bash
# Only runs stacks with changes since main
terramate run --changed -- terraform plan

# Run stacks in dependency order
terramate run -- terraform apply
```

**Why Terramate over alternatives:**
| Tool | Pros | Cons |
|------|------|------|
| **Terramate** | Lightweight, no infra, works with any CI | Newer, smaller community |
| Atlantis | Pull request automation | Requires hosting, GitHub/GitLab only |
| Spacelift | Full featured, policies | SaaS cost, vendor lock-in |
| TFC/TFE | Official HashiCorp | Expensive at scale |

**ROI for this project:**

- Current: 2 environments, simple structure - Terramate is overkill
- Future: 5+ environments, multiple regions - Terramate saves significant CI time

**When I'd recommend it:**

- 3+ environments OR
- Multi-region with shared components OR
- Team of 3+ platform engineers

#### Option 2: Keep Current Approach (Recommended for Now)

**Why it's fine:**

- Only 2 environments (dev/prod)
- Simple dependency graph (no cross-stack dependencies)
- Pipeline is ~100 lines, easy to maintain
- No additional tooling to learn

**Incremental improvement - add change detection without Terramate:**

```yaml
# In Azure DevOps pipeline
- script: |
    # Only run terraform if files changed
    CHANGED=$(git diff --name-only HEAD~1 HEAD -- terraform/)
    if [ -n "$CHANGED" ]; then
      echo "Terraform changes detected, running plan..."
      terraform plan
    else
      echo "No terraform changes, skipping"
    fi
```

---

### How to Frame This in Interview

**Don't say:** "I made mistakes, here's what I'd fix"

**Do say:** "Given the 6-10 hour timebox, I focused on production-ready fundamentals - circuit breaker, retries, managed identity, structured logging. Here's my prioritized v2 backlog based on actual gaps..."

**What I intentionally deferred:**

- Alerts - requires operational context (PagerDuty integration, on-call rotation)
- Rate limiting - requires Redis infrastructure decision
- Contract testing - requires RiskShield API access for verification

**Key insight:** The solution is production-ready for a controlled rollout. Improvements are about operational maturity, not missing fundamentals.

---

_Document Version: 1.0_
_Created: 2026-02-24_
_For: Pollinate Platform Engineering Interview_
