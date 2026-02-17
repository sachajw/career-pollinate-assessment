# ADR-002: Python Runtime, Resilience & Observability

**Status:** Accepted
**Date:** 2026-02-14
**Decision Makers:** Platform Engineering Team
**Technical Story:** RiskShield API Integration Platform

## Context

The RiskShield integration service requires:
- A runtime platform for the REST API
- Resilience patterns (timeouts, retries, correlation IDs)
- Observability (logging, metrics, tracing)

The technical assessment explicitly requires:
- Proper error handling
- Logging
- Timeout handling
- Retry logic
- Correlation IDs

## Decision

We will use **Python 3.13 with FastAPI** as the runtime, with **tenacity for retries**, **httpx with timeouts**, and **structured logging with correlation IDs**.

---

## Part 1: Runtime Selection

### Decision: Python 3.13 + FastAPI

| Criterion                 | Weight | Python/FastAPI | .NET 8     | Go         | Node.js    |
| ------------------------- | ------ | -------------- | ---------- | ---------- | ---------- |
| **Development Speed**     | High   | ⭐⭐⭐⭐⭐     | ⭐⭐⭐⭐   | ⭐⭐⭐     | ⭐⭐⭐⭐⭐ |
| **Type Safety**           | High   | ⭐⭐⭐⭐       | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐   |
| **Async I/O Performance** | High   | ⭐⭐⭐⭐       | ⭐⭐⭐⭐   | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Azure SDK Quality**     | High   | ⭐⭐⭐⭐       | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐   | ⭐⭐⭐⭐⭐ |
| **Team Familiarity**      | Medium | ⭐⭐⭐⭐⭐     | ⭐⭐⭐     | ⭐⭐⭐     | ⭐⭐⭐⭐   |
| **REST API Ecosystem**    | High   | ⭐⭐⭐⭐⭐     | ⭐⭐⭐⭐   | ⭐⭐⭐⭐   | ⭐⭐⭐⭐⭐ |

### Python Version: 3.13

**Why 3.13 over 3.12 or 3.14:**

| Version | Release | Status | Decision |
| ------- | ------- | ------ | -------- |
| 3.12    | Oct 2023| Stable | ⚠️ Missing JIT, older error messages |
| **3.13**| **Oct 2024** | **Recommended** | ✅ Best balance of stability + features |
| 3.14    | Oct 2025| Too new | ❌ Only 4 months old, library risk |

**Python 3.13 Benefits:**
- 16 months production hardening
- Experimental JIT compiler (10-30% faster)
- Enhanced error messages
- Full Azure SDK support
- FastAPI 0.109+ compatible

### Package Manager: uv

**Why uv over pip:**
- 10-100x faster dependency resolution
- Rust-based, highly optimized
- Lock file support (`uv.lock`)
- Drop-in replacement for pip

---

## Part 2: Resilience Patterns

### 2.1 Timeout Handling

**Decision:** Use `httpx` with configurable timeouts

```python
# src/services/riskshield_client.py
import httpx
from src.core.config import settings

# Timeout configuration
HTTP_TIMEOUT = httpx.Timeout(
    connect=5.0,      # Connection timeout
    read=10.0,        # Read timeout (RiskShield API response)
    write=5.0,        # Write timeout
    pool=5.0          # Pool timeout
)

class RiskShieldClient:
    def __init__(self):
        self.client = httpx.AsyncClient(
            base_url=settings.RISKSHIELD_API_URL,
            timeout=HTTP_TIMEOUT,
            headers={"X-API-Key": self._get_api_key()}
        )

    async def score(self, request: ValidateRequest) -> RiskScoreResponse:
        try:
            response = await self.client.post(
                "/v1/score",
                json=request.model_dump()
            )
            response.raise_for_status()
            return RiskScoreResponse(**response.json())
        except httpx.TimeoutException as e:
            raise RiskShieldTimeoutError(f"RiskShield API timeout: {e}")
```

**Timeout Values Rationale:**

| Operation | Timeout | Rationale |
|-----------|---------|-----------|
| Connect   | 5s      | Network connection should be fast |
| Read      | 10s     | External API processing time |
| Write     | 5s      | Small payload, should be quick |
| Pool      | 5s      | Connection pool acquisition |

### 2.2 Retry Logic

**Decision:** Use `tenacity` library with exponential backoff

```python
# src/services/riskshield_client.py
from tenacity import (
    retry,
    stop_after_attempt,
    wait_exponential,
    retry_if_exception_type,
    before_sleep_log
)
import structlog

logger = structlog.get_logger()

# Retry configuration
@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=1, max=10),
    retry=retry_if_exception_type(httpx.HTTPStatusError),
    before_sleep=before_sleep_log(logger, log_level="WARNING"),
    reraise=True
)
async def score_with_retry(self, request: ValidateRequest) -> RiskScoreResponse:
    """
    Retry RiskShield API calls with exponential backoff.

    Retries on:
    - 5xx server errors (temporary issues)
    - 429 rate limiting (with backoff)

    Does NOT retry on:
    - 4xx client errors (bad request, unauthorized)
    - Timeout errors (separate handling)
    """
    response = await self.client.post("/v1/score", json=request.model_dump())

    # Only retry on retryable status codes
    if response.status_code >= 500 or response.status_code == 429:
        raise httpx.HTTPStatusError(
            f"Retryable error: {response.status_code}",
            request=response.request,
            response=response
        )

    response.raise_for_status()
    return RiskScoreResponse(**response.json())
```

**Retry Strategy:**

| Retry # | Wait Time | Cumulative |
|---------|-----------|------------|
| 1st     | 1s        | 1s         |
| 2nd     | 2s        | 3s         |
| 3rd     | 4s        | 7s         |

**Max wait with retries:** 7s + original request time

### 2.3 Correlation IDs

**Decision:** Use `structlog` with correlation ID middleware

```python
# src/middleware/correlation.py
import uuid
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response
import structlog

class CorrelationIDMiddleware(BaseHTTPMiddleware):
    """
    Add correlation ID to all requests for distributed tracing.
    """
    CORRELATION_ID_HEADER = "X-Correlation-ID"

    async def dispatch(self, request: Request, call_next) -> Response:
        # Use existing correlation ID from header or generate new one
        correlation_id = request.headers.get(
            self.CORRELATION_ID_HEADER,
            str(uuid.uuid4())
        )

        # Bind to structlog context
        structlog.contextvars.bind_contextvars(correlation_id=correlation_id)

        response = await call_next(request)

        # Add correlation ID to response header
        response.headers[self.CORRELATION_ID_HEADER] = correlation_id

        return response

# src/main.py
from fastapi import FastAPI
from src.middleware.correlation import CorrelationIDMiddleware

app = FastAPI()
app.add_middleware(CorrelationIDMiddleware)
```

**Correlation ID Flow:**

```
Client Request
     │
     ▼ X-Correlation-ID: abc-123 (or generated)
┌─────────────┐
│  API Layer  │ ──── Log: "Request received" [correlation_id=abc-123]
└─────────────┘
     │
     ▼
┌─────────────┐
│  Service    │ ──── Log: "Calling RiskShield" [correlation_id=abc-123]
└─────────────┘
     │
     ▼ X-Correlation-ID: abc-123 (propagated to external API)
┌─────────────┐
│ RiskShield  │
└─────────────┘
     │
     ▼
┌─────────────┐
│  Response   │ ──── Log: "Response sent" [correlation_id=abc-123]
└─────────────┘
     │
     ▼ X-Correlation-ID: abc-123 (returned to client)
```

---

## Part 3: Observability

### 3.1 Structured Logging

**Decision:** Use `structlog` with JSON output

```python
# src/core/logging.py
import logging
import sys
import structlog
from src.core.config import settings

def setup_logging():
    """Configure structured logging for the application."""

    # Configure structlog
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.StackInfoRenderer(),
            structlog.dev.set_exc_info,
            structlog.processors.TimeStamper(fmt="iso"),
            # JSON output for production, console for dev
            structlog.processors.JSONRenderer()
            if settings.ENVIRONMENT == "production"
            else structlog.dev.ConsoleRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(
            logging.INFO if settings.ENVIRONMENT == "production" else logging.DEBUG
        ),
        logger_factory=structlog.PrintLoggerFactory(),
    )

# Usage in services
logger = structlog.get_logger()

async def validate_applicant(request: ValidateRequest):
    logger.info(
        "validation_started",
        first_name=request.firstName,
        id_number_masked=request.idNumber[:6] + "*******"
    )

    try:
        result = await riskshield_client.score(request)
        logger.info("validation_completed", risk_score=result.riskScore)
        return result
    except Exception as e:
        logger.error("validation_failed", error=str(e))
        raise
```

**Log Output Example:**

```json
{
  "event": "validation_started",
  "level": "info",
  "timestamp": "2026-02-14T10:30:45.123456Z",
  "correlation_id": "abc-123-def-456",
  "first_name": "Jane",
  "id_number_masked": "900101*******"
}
```

### 3.2 Metrics

**Decision:** Use Application Insights via OpenCensus

```python
# src/core/telemetry.py
from opencensus.ext.azure import metrics_exporter
from src.core.config import settings

# Application Insights metrics exporter
exporter = metrics_exporter.new_metrics_exporter(
    connection_string=settings.APPLICATIONINSIGHTS_CONNECTION_STRING
)

# Custom metrics are automatically collected:
# - Request rate
# - Response time
# - Error rate
# - Dependency calls (RiskShield API)
```

**Key Metrics Collected:**

| Metric | Type | Purpose |
|--------|------|---------|
| Request count | Counter | Traffic volume |
| Request duration | Histogram | Performance |
| Error rate | Counter | Health monitoring |
| RiskShield latency | Histogram | External API performance |
| Retry count | Counter | Resilience monitoring |

### 3.3 Distributed Tracing

**Decision:** Application Insights auto-instrumentation

```python
# src/core/telemetry.py
from opencensus.ext.azure.trace_exporter import AzureExporter
from opencensus.trace.samplers import ProbabilitySampler
from opencensus.trace.tracer import Tracer
from src.core.config import settings

tracer = Tracer(
    exporter=AzureExporter(
        connection_string=settings.APPLICATIONINSIGHTS_CONNECTION_STRING
    ),
    sampler=ProbabilitySampler(1.0)  # 100% sampling for now
)

# Tracing is automatic for:
# - HTTP requests
# - Database calls
# - External API calls (httpx)
```

**Trace Flow:**

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Application Insights Trace                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  POST /validate (250ms total)                                       │
│  ├── Validation middleware (5ms)                                    │
│  ├── Request parsing (2ms)                                          │
│  ├── RiskShield API call (230ms)                                    │
│  │   ├── Connection (10ms)                                          │
│  │   ├── Request sent (5ms)                                         │
│  │   ├── Processing (200ms)                                         │
│  │   └── Response received (15ms)                                   │
│  └── Response serialization (8ms)                                   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 4: Error Handling

### Error Handling Strategy

```python
# src/api/v1/exceptions.py
from fastapi import HTTPException, Request
from fastapi.responses import JSONResponse
import structlog

logger = structlog.get_logger()

class RiskShieldError(Exception):
    """Base exception for RiskShield errors."""
    pass

class RiskShieldTimeoutError(RiskShieldError):
    """RiskShield API timeout."""
    pass

class RiskShieldUnavailableError(RiskShieldError):
    """RiskShield API unavailable after retries."""
    pass

# Exception handlers
@app.exception_handler(RiskShieldTimeoutError)
async def timeout_handler(request: Request, exc: RiskShieldTimeoutError):
    logger.error("riskshield_timeout", error=str(exc))
    return JSONResponse(
        status_code=504,
        content={
            "error": "gateway_timeout",
            "message": "Risk validation service timed out. Please try again.",
            "correlation_id": structlog.contextvars.get_contextvars().get("correlation_id")
        }
    )

@app.exception_handler(RiskShieldUnavailableError)
async def unavailable_handler(request: Request, exc: RiskShieldUnavailableError):
    logger.error("riskshield_unavailable", error=str(exc))
    return JSONResponse(
        status_code=503,
        content={
            "error": "service_unavailable",
            "message": "Risk validation service is temporarily unavailable. Please try again later.",
            "correlation_id": structlog.contextvars.get_contextvars().get("correlation_id")
        }
    )
```

**Error Response Format:**

```json
{
  "error": "service_unavailable",
  "message": "Risk validation service is temporarily unavailable.",
  "correlation_id": "abc-123-def-456"
}
```

---

## Summary: Technical Assessment Compliance

| Assessment Requirement | Implementation | Location |
|------------------------|----------------|----------|
| **Language** (Python, etc.) | Python 3.13 + FastAPI | Part 1 |
| **Error handling** | Exception handlers with structured responses | Part 4 |
| **Logging** | structlog with JSON output | Part 3.1 |
| **Timeout handling** | httpx with 10s read timeout | Part 2.1 |
| **Retry logic** | tenacity with exponential backoff | Part 2.2 |
| **Correlation IDs** | Middleware + structlog context | Part 2.3 |

---

## Consequences

### Positive
- ✅ **Fast Development**: FastAPI + Pydantic = rapid API development
- ✅ **Resilience**: Timeouts + retries handle transient failures
- ✅ **Observability**: Full visibility into requests and errors
- ✅ **Tracing**: Correlation IDs link all logs for a request
- ✅ **Type Safety**: Pydantic validation + mypy

### Negative
- ⚠️ **Performance**: Python slower than Go (adequate for 1000 req/min)
- ⚠️ **Cold Start**: 2-3s (mitigated by min replicas in prod)

---

## Related Decisions

- [ADR-001: Azure Container Apps](./001-azure-container-apps.md)
- [ADR-003: Managed Identity & Security](./003-managed-identity-security.md)

## References

- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Tenacity Retry Library](https://tenacity.readthedocs.io/)
- [Structlog Documentation](https://www.structlog.org/)
- [httpx Timeout Documentation](https://www.python-httpx.org/advanced/#timeout-configuration)
- [Application Insights Python](https://docs.microsoft.com/en-us/azure/azure-monitor/app/opencensus-python)

## Review & Approval

| Role                      | Name   | Date       | Status      |
| ------------------------- | ------ | ---------- | ----------- |
| Solution Architect        | [Name] | 2026-02-14 | ✅ Approved |
| Platform Engineering Lead | [Name] | 2026-02-14 | ✅ Approved |

---

**Last Updated:** 2026-02-14
**Next Review:** 2026-08-14 (6 months)
