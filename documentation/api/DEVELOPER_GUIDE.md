# Developer Guide

This guide covers development practices, architecture decisions, and contribution guidelines for the Risk Scoring API.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      FastAPI Application                     │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Routes    │  │   Models    │  │     Middleware      │  │
│  │  (api/v1)   │──│  (Pydantic) │──│  (CORS, Rate Limit) │  │
│  └──────┬──────┘  └─────────────┘  └─────────────────────┘  │
│         │                                                    │
│         ▼                                                    │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              RiskShield Client                       │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌───────────┐  │    │
│  │  │ HTTP Client  │  │ Circuit      │  │  Retry    │  │    │
│  │  │  (httpx)     │  │ Breaker      │  │  Logic    │  │    │
│  │  └──────────────┘  └──────────────┘  └───────────┘  │    │
│  └─────────────────────────┬───────────────────────────┘    │
└────────────────────────────┼────────────────────────────────┘
                             │
                             ▼
              ┌──────────────────────────┐
              │    RiskShield API        │
              │    (External Service)    │
              └──────────────────────────┘
```

## Technology Stack

| Component | Technology | Purpose |
|-----------|------------|---------|
| Web Framework | FastAPI | Async REST API framework |
| Validation | Pydantic | Data validation and serialization |
| HTTP Client | httpx | Async HTTP requests to RiskShield |
| Retry Logic | tenacity | Exponential backoff retries |
| Rate Limiting | slowapi | Request rate limiting |
| Logging | structlog | Structured JSON logging |
| Secrets | Azure Key Vault | Secure credential storage |
| Identity | Azure Managed Identity | Passwordless authentication |

## Design Patterns

### 1. Layered Architecture

The application follows a clean layered architecture:

- **API Layer** (`src/api/`): Request handling, response formatting
- **Service Layer** (`src/services/`): Business logic, external integrations
- **Model Layer** (`src/models/`): Data structures and validation
- **Core Layer** (`src/core/`): Configuration, logging, utilities

### 2. Dependency Injection

Settings are injected using `lru_cache` for singleton pattern:

```python
@lru_cache
def get_settings() -> Settings:
    return Settings()

# Usage
settings = get_settings()
```

### 3. Circuit Breaker

The RiskShield client implements a circuit breaker to prevent cascading failures:

```python
class CircuitBreaker:
    """
    States:
    - CLOSED: Normal operation
    - OPEN: Rejecting requests (failure threshold exceeded)
    - HALF_OPEN: Testing recovery
    """
```

### 4. Repository Pattern (Future)

For database operations, use the repository pattern to abstract data access.

## Adding New Features

### Adding a New Endpoint

1. **Define the route** in `src/api/v1/routes.py`:

```python
@router.post(
    "/new-endpoint",
    response_model=NewResponse,
    responses={400: {"model": ErrorResponse}},
    summary="Endpoint summary",
)
@limiter.limit("100/minute")
async def new_endpoint(request: Request, data: NewRequest) -> NewResponse:
    """Endpoint description."""
    # Implementation
    return NewResponse(...)
```

2. **Create Pydantic models** in `src/models/schemas.py`:

```python
class NewRequest(BaseModel):
    field: str = Field(..., description="Field description")

class NewResponse(BaseModel):
    result: str
```

3. **Add business logic** in `src/services/` if needed

4. **Write tests** in `tests/integration/test_api.py`

5. **Update documentation**

### Adding a New Service Client

1. **Create the client** in `src/services/`:

```python
class NewServiceClient:
    def __init__(self) -> None:
        self._settings = get_settings()
        self._client: httpx.AsyncClient | None = None

    async def _get_client(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(timeout=30.0)
        return self._client

    async def do_something(self) -> Result:
        client = await self._get_client()
        # Make request, handle errors
        ...

    async def close(self) -> None:
        if self._client:
            await self._client.aclose()
            self._client = None
```

2. **Register lifecycle** in `src/main.py`:

```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    yield
    # Shutdown
    await close_new_service_client()
```

## Error Handling

### Exception Hierarchy

```python
RiskShieldError (base)
├── RiskShieldAuthError (401)
├── RiskShieldRateLimitError (429)
├── RiskShieldTimeoutError (504)
└── RiskShieldServerError (503)
```

### Error Response Format

All errors follow a consistent format:

```json
{
  "error": "ERROR_CODE",
  "message": "Human-readable message",
  "correlationId": "uuid",
  "details": []  // Optional
}
```

## Logging Guidelines

### Log Levels

| Level | Use Case |
|-------|----------|
| DEBUG | Detailed diagnostic information |
| INFO | Normal operational events |
| WARNING | Unexpected but handled situations |
| ERROR | Errors that affect request processing |

### Structured Logging

Always use structured logging with context:

```python
from src.core.logging import get_logger

logger = get_logger(__name__)

# Good
logger.info(
    "validation_request_completed",
    risk_score=72,
    risk_level="MEDIUM",
    duration_ms=150,
)

# Avoid
logger.info(f"Validation completed: score={score}")
```

### Sensitive Data

Never log:
- API keys
- ID numbers (log prefix only: `"1234***"`)
- Names (unless anonymized)
- Any PII

The logging module automatically redacts sensitive fields.

## Testing Strategy

### Test Categories

| Type | Location | Purpose |
|------|----------|---------|
| Unit | `tests/unit/` | Test individual functions/classes |
| Integration | `tests/integration/` | Test API endpoints |
| E2E | `tests/e2e/` | Full system tests (future) |

### Writing Unit Tests

```python
import pytest
from src.models import ValidationRequest

class TestValidationRequest:
    def test_valid_request(self):
        request = ValidationRequest(
            first_name="John",
            last_name="Doe",
            id_number="9001011234088",
        )
        assert request.first_name == "John"

    def test_invalid_id_number(self):
        with pytest.raises(ValidationError):
            ValidationRequest(
                first_name="John",
                last_name="Doe",
                id_number="invalid",
            )
```

### Writing Integration Tests

```python
from unittest.mock import patch, AsyncMock
from fastapi.testclient import TestClient

class TestValidateEndpoint:
    @patch("src.api.v1.routes.get_riskshield_client")
    def test_validate_success(self, mock_get_client, client):
        mock_client = mock_get_client.return_value
        mock_client.validate = AsyncMock(
            return_value=RiskShieldResult(risk_score=50, risk_level="MEDIUM")
        )

        response = client.post(
            "/api/v1/validate",
            json={"firstName": "Jane", "lastName": "Doe", "idNumber": "9001011234088"},
        )

        assert response.status_code == 200
```

### Test Coverage

Target: 80%+ coverage

```bash
# Run with coverage
uv run pytest --cov=src --cov-report=html

# View report
open htmlcov/index.html
```

## Code Style

### Formatting

We use Ruff for formatting and linting:

```bash
# Check style
uv run ruff check src/

# Auto-format
uv run ruff format src/
```

### Type Hints

All functions must have type hints:

```python
# Good
async def validate(self, first_name: str, last_name: str) -> Result:
    ...

# Avoid
async def validate(self, first_name, last_name):
    ...
```

### Docstrings

Use Google-style docstrings:

```python
async def validate_applicant(
    first_name: str,
    last_name: str,
    id_number: str,
) -> RiskShieldResult:
    """Validate a loan applicant.

    Args:
        first_name: Applicant's first name.
        last_name: Applicant's last name.
        id_number: South African ID number.

    Returns:
        RiskShieldResult containing risk score and level.

    Raises:
        RiskShieldAuthError: If authentication fails.
        RiskShieldTimeoutError: If request times out.
    """
```

## Security Considerations

### Input Validation

- All inputs validated via Pydantic
- SA ID number validated with Luhn algorithm
- Request size limits enforced

### Authentication

- Bearer token authentication required
- API keys stored in Azure Key Vault
- No credentials in code or logs

### Rate Limiting

- Prevents abuse and DoS attacks
- Per-IP rate limiting
- Configurable limits

### Data Protection

- No PII stored permanently
- Logs redact sensitive data
- HTTPS only in production

## Performance Guidelines

### Async Operations

Always use async for I/O operations:

```python
# Good
async with httpx.AsyncClient() as client:
    response = await client.get(url)

# Avoid (blocks event loop)
response = requests.get(url)
```

### Connection Pooling

HTTP clients are reused via singleton pattern:

```python
async def _get_client(self) -> httpx.AsyncClient:
    if self._client is None:
        self._client = httpx.AsyncClient()
    return self._client
```

### Timeouts

Always set timeouts:

```python
httpx.AsyncClient(timeout=httpx.Timeout(30.0))
```

## Troubleshooting

### Common Issues

**Import errors:**
```bash
# Ensure virtual environment is active
source .venv/bin/activate
uv sync
```

**Type checking errors:**
```bash
# Run mypy to identify issues
uv run mypy src/
```

**Test failures:**
```bash
# Run with verbose output
uv run pytest -v --tb=long
```

### Debugging

Enable debug logging:

```bash
export LOG_LEVEL=DEBUG
uv run uvicorn src.main:app --reload
```

Use the correlation ID to trace requests through logs:

```bash
grep "a1b2c3d4-e5f6-7890-abcd-ef1234567890" logs/app.log
```

## Contributing

1. Create a feature branch
2. Make changes with tests
3. Run quality checks:

```bash
uv run ruff check src/
uv run ruff format src/
uv run mypy src/
uv run pytest --cov=src
```

4. Submit pull request with description
5. Address review feedback
