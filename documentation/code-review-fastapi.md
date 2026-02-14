# FastAPI Code Review - RiskShield API

**Date**: 2026-02-14
**Reviewer**: Claude Code
**Scope**: Application FastAPI code (`app/src/`)

## Summary

Overall, this is a **well-structured, production-ready FastAPI application**. Good separation of concerns, proper Pydantic v2 usage, and comprehensive error handling. However, there are several issues that need attention, including potential event loop blocking and security concerns.

---

## Files Reviewed

| File | Purpose |
|------|---------|
| `app/src/main.py` | FastAPI application entry point |
| `app/src/api/v1/routes.py` | API v1 route definitions |
| `app/src/models/schemas.py` | Pydantic models for request/response |
| `app/src/services/riskshield_client.py` | RiskShield API client service |
| `app/src/core/config.py` | Application configuration |
| `app/src/core/logging.py` | Logging configuration |
| `app/tests/conftest.py` | Pytest fixtures |
| `app/tests/integration/test_api.py` | Integration tests |
| `app/pyproject.toml` | Project configuration |

---

## Findings

### CRITICAL

#### 1. Sync Key Vault Call Blocks Event Loop

**File**: `app/src/services/riskshield_client.py:191-207`

```python
async def _get_api_key(self) -> str:
    # ...
    credential = DefaultAzureCredential()
    client = SecretClient(...)  # Sync client!
    secret = client.get_secret("RISKSHIELD-API-KEY")  # Blocking call!
```

**Problem**: Using synchronous Azure SDK in an async method blocks the event loop. Under load, this will cause request queuing and latency spikes.

**Fix**: Use `azure.keyvault.secrets.aio` async client:

```python
from azure.keyvault.secrets.aio import SecretClient as AsyncSecretClient

async def _get_api_key(self) -> str:
    if self._api_key:
        return self._api_key

    if self._settings.riskshield_api_key:
        self._api_key = self._settings.riskshield_api_key
        return self._api_key

    if self._settings.key_vault_url:
        try:
            from azure.identity.aio import DefaultAzureCredential as AsyncDefaultAzureCredential

            async with AsyncDefaultAzureCredential() as credential:
                async with AsyncSecretClient(
                    vault_url=self._settings.key_vault_url,
                    credential=credential,
                ) as client:
                    secret = await client.get_secret("RISKSHIELD-API-KEY")
                    self._api_key = secret.value
                    logger.info("api_key_loaded_from_key_vault")
                    return self._api_key
        except Exception as e:
            logger.error("failed_to_load_api_key_from_key_vault", error=str(e))
            raise RiskShieldAuthError("Failed to load API key from Key Vault") from e

    raise RiskShieldAuthError("No API key configured")
```

---

#### 2. Deprecated asyncio.get_event_loop() in CircuitBreaker

**File**: `app/src/services/riskshield_client.py:125,148`

```python
elapsed = asyncio.get_event_loop().time() - self._last_failure_time
```

**Problem**: `asyncio.get_event_loop()` is deprecated in Python 3.10+ and can cause issues in some async contexts. In production with high concurrency, this can lead to subtle bugs.

**Fix**: Use `time.monotonic()` instead for timing:

```python
import time

class CircuitBreaker:
    def __init__(self, ...):
        # ...
        self._last_failure_time: float | None = None

    def can_execute(self) -> bool:
        # ...
        if self._state == CircuitState.OPEN:
            if self._last_failure_time is None:
                self._state = CircuitState.HALF_OPEN
                return True

            elapsed = time.monotonic() - self._last_failure_time  # Fixed
            if elapsed >= self.recovery_timeout:
                self._state = CircuitState.HALF_OPEN
                self._half_open_calls = 0
                return True
            return False
        # ...

    def record_failure(self) -> None:
        self._failure_count += 1
        self._last_failure_time = time.monotonic()  # Fixed
        # ...
```

---

### HIGH

#### 3. CORS Default allow_origins=["*"]

**File**: `app/src/core/config.py:102`

```python
cors_origins: list[str] = Field(default=["*"], ...)
cors_allow_credentials: bool = Field(default=False, ...)
```

**Problem**: While `allow_credentials=False` mitigates the immediate risk, having `["*"]` as default is dangerous. If someone accidentally enables credentials, it creates a CSRF vulnerability.

**Fix**:

```python
cors_origins: list[str] = Field(
    default=[],  # Empty by default - must be explicitly set
    description="Allowed CORS origins (required in production)",
)
```

---

#### 4. Import Inside Function

**File**: `app/src/main.py:113,150`

```python
async def validation_exception_handler(...):
    import uuid  # Inside function!
```

**Problem**: Imports inside functions are a code smell and can mask circular import issues.

**Fix**: Move to top of file:

```python
import uuid
from contextlib import asynccontextmanager
from typing import Any

import uvicorn
from fastapi import FastAPI, Request, status
# ...
```

Same issue in `app/src/api/v1/routes.py:72`.

---

#### 5. Literal Import at Bottom of File

**File**: `app/src/models/schemas.py:277-278`

```python
# Import Literal for type hints
from typing import Literal  # At the BOTTOM of the file!
```

**Problem**: Importing `Literal` after it's used causes a `NameError` if the classes are moved. The code currently "works" because `HealthResponse` and `ReadyResponse` are defined at the bottom, but this is fragile.

**Fix**: Move `Literal` import to the top with other imports:

```python
from enum import Enum
from typing import Any, Literal
from uuid import UUID, uuid4

from pydantic import BaseModel, Field, field_validator, model_validator
```

---

### MEDIUM

#### 6. UUID Type Inconsistency

**File**: `app/src/api/v1/routes.py:73` and `app/src/main.py:114,151`

```python
# routes.py
correlation_id = uuid.uuid4()
set_correlation_id(str(correlation_id))  # Converts to string

# main.py
correlation_id = uuid.uuid4()  # UUID object passed directly
```

**Problem**: Inconsistent handling - sometimes UUID objects, sometimes strings.

**Fix**: Be consistent - the schema expects `UUID` type, so pass UUID objects directly:

```python
correlation_id = uuid.uuid4()  # Keep as UUID everywhere
# Only convert to str for logging/tracing if needed
```

---

#### 7. Settings Cached with @lru_cache Without Parentheses

**File**: `app/src/core/config.py:160-161`

```python
@lru_cache
def get_settings() -> Settings:
    return Settings()
```

**Problem**: `@lru_cache` without parentheses is deprecated syntax. Also, settings can't be reloaded during tests without cache clearing.

**Fix**:

```python
@lru_cache()  # Add parentheses
def get_settings() -> Settings:
    return Settings()


# Add reset function for tests:
def reset_settings() -> None:
    """Clear settings cache (for testing)."""
    get_settings.cache_clear()
```

---

#### 8. Missing SlowAPI Middleware Configuration

**File**: `app/src/api/v1/routes.py:54`

```python
@limiter.limit(f"{settings.rate_limit_requests}/minute")
```

**Problem**: The limiter is configured per-route but the SlowAPI middleware and exception handler may not be properly registered in the main app.

**Fix**: Ensure slowapi is properly configured in `main.py`:

```python
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

limiter = Limiter(key_func=get_remote_address)

def create_app() -> FastAPI:
    app = FastAPI(...)
    app.state.limiter = limiter
    app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
    # ...
```

---

#### 9. Redundant Risk Level Logic

**File**: `app/src/api/v1/routes.py:92-94`

```python
risk_level=RiskLevel(result.risk_level.lower())
if result.risk_level.lower() in [e.value.lower() for e in RiskLevel]
else RiskLevel.from_score(result.risk_score),
```

**Problem**: This ternary expression checks if the risk level is valid, but the `model_validator` in `ValidationResponse` already handles this normalization.

**Fix**: Simplify - let the model validator handle it:

```python
response = ValidationResponse(
    risk_score=result.risk_score,
    risk_level=RiskLevel.from_score(result.risk_score),  # Always derive from score
    correlation_id=correlation_id,
    additional_data=result.additional_data,
)
```

---

### LOW

#### 10. Unused Imports

**File**: `app/src/api/v1/routes.py:3-5`

```python
import time  # Not used
from collections import defaultdict  # Not used
from ipaddress import ip_address  # Not used
```

**Fix**: Remove these unused imports.

---

#### 11. Hardcoded Retry Count Ignores Settings

**File**: `app/src/services/riskshield_client.py:221`

```python
@retry(
    stop=stop_after_attempt(3),  # Hardcoded, ignores settings.riskshield_max_retries
```

**Problem**: The `riskshield_max_retries` setting is not used.

**Fix**: This requires refactoring since decorators are evaluated at definition time. Consider:

```python
async def validate(self, ...) -> RiskShieldResult:
    for attempt in range(self._settings.riskshield_max_retries):
        try:
            return await self._do_validate(...)
        except RiskShieldServerError:
            if attempt == self._settings.riskshield_max_retries - 1:
                raise
            await asyncio.sleep(self._settings.riskshield_retry_delay * (2 ** attempt))
```

---

#### 12. Test Client Uses Sync TestClient

**File**: `app/tests/conftest.py`

```python
from fastapi.testclient import TestClient  # Sync client
```

**Problem**: For true async testing, consider using `httpx.AsyncClient`.

**Fix**:

```python
import pytest
from httpx import AsyncClient, ASGITransport

@pytest.fixture
async def async_client(test_settings):
    with patch("src.main.get_settings", return_value=test_settings):
        app = create_app()
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test"
        ) as client:
            yield client
```

---

## Dependency Versions

| Package | Current | Latest (Jan 2026) | Recommendation |
|---------|---------|-------------------|----------------|
| FastAPI | >=0.109.0 | 0.128.0 | Update - includes security fixes |
| Pydantic | >=2.5.0 | 2.11.7 | Update |
| uvicorn | >=0.27.0 | 0.35.0 | Update |
| httpx | >=0.26.0 | 0.28.0 | OK |

---

## Good Patterns Observed

- Proper Pydantic v2 usage with `Field()`, `field_validator`, `model_validator`
- Correct `model_config = ConfigDict(from_attributes=True)` pattern
- Structured logging with correlation IDs using `structlog`
- Circuit breaker implementation for fault tolerance
- Proper exception hierarchy with custom exceptions
- Health/readiness endpoints for Kubernetes probes
- Rate limiting with `slowapi`
- Comprehensive test coverage structure

---

## Action Items

| # | Priority | Issue | File | Est. Effort |
|---|----------|-------|------|-------------|
| 1 | CRITICAL | Sync Key Vault call blocks event loop | `riskshield_client.py:191-207` | 30 min |
| 2 | CRITICAL | Deprecated `get_event_loop()` | `riskshield_client.py:125,148` | 15 min |
| 3 | HIGH | CORS default `["*"]` | `config.py:102` | 5 min |
| 4 | HIGH | Import inside function | `main.py:113,150` | 5 min |
| 5 | HIGH | Import at bottom of file | `schemas.py:277-278` | 5 min |
| 6 | MEDIUM | UUID type inconsistency | `routes.py:73` | 10 min |
| 7 | MEDIUM | Settings cache syntax | `config.py:160` | 5 min |
| 8 | LOW | Unused imports | `routes.py:3-5` | 2 min |
| 9 | LOW | Hardcoded retry count | `riskshield_client.py:221` | 20 min |
| 10 | INFO | Update dependencies | `pyproject.toml` | 10 min |

---

## Next Steps

1. Address CRITICAL issues first (event loop blocking)
2. Fix HIGH priority security concerns (CORS, imports)
3. Run full test suite after changes
4. Consider adding async integration tests
5. Update dependencies to latest versions
