# Risk Scoring API

A FastAPI-based REST API for loan applicant fraud risk validation using RiskShield.

## Features

- **Risk Validation**: Submit applicant details and receive a risk score (0-100)
- **Risk Classification**: Automatic categorization (LOW, MEDIUM, HIGH, CRITICAL)
- **Correlation IDs**: Every request gets a unique ID for distributed tracing
- **Rate Limiting**: Configurable requests per minute per client
- **Circuit Breaker**: Fault tolerance for upstream service failures
- **Structured Logging**: JSON logs with correlation IDs for observability
- **Azure Key Vault Integration**: Secure secret management
- **OpenAPI Documentation**: Auto-generated API docs

## Quick Start

### Prerequisites

- Python 3.13+
- [uv](https://docs.astral.sh/uv/) package manager
- Docker (optional)

### Local Development

```bash
# Install uv (if not installed)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Navigate to app directory
cd app

# Install dependencies
uv sync

# Activate virtual environment
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Set up environment variables
cp .env.example .env
# Edit .env with your configuration

# Run development server with hot reload
uv run uvicorn src.main:app --reload --port 8080
```

The API will be available at `http://localhost:8080`

- **API Documentation**: http://localhost:8080/docs
- **ReDoc**: http://localhost:8080/redoc
- **Health Check**: http://localhost:8080/health

### Docker

```bash
# Build image
docker build -t risk-scoring-api:latest .

# Run container
docker run -p 8080:8080 \
  -e ENVIRONMENT=dev \
  -e RISKSHIELD_API_KEY=your-key \
  risk-scoring-api:latest

# Run with environment file
docker run -p 8080:8080 --env-file .env risk-scoring-api:latest
```

## API Reference

### POST /api/v1/validate

Validates a loan applicant and returns their fraud risk score.

**Request:**

```bash
curl -X POST http://localhost:8080/api/v1/validate \
  -H "Content-Type: application/json" \
  -d '{
    "firstName": "Jane",
    "lastName": "Doe",
    "idNumber": "9001011234088"
  }'
```

**Success Response (200):**

```json
{
  "riskScore": 72,
  "riskLevel": "MEDIUM",
  "correlationId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "additionalData": {
    "factors": ["high_debt_ratio", "recent_inquiries"]
  }
}
```

**Error Response (400):**

```json
{
  "error": "VALIDATION_ERROR",
  "message": "Request validation failed",
  "correlationId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "details": [
    {
      "field": "idNumber",
      "message": "ID number must be exactly 13 digits",
      "code": "string_too_short"
    }
  ]
}
```

### Health Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /health` | Health check for load balancers |
| `GET /ready` | Readiness check for Kubernetes |

### Risk Levels

| Level | Score Range | Description |
|-------|-------------|-------------|
| `LOW` | 0-29 | Low fraud risk, proceed with standard checks |
| `MEDIUM` | 30-59 | Moderate risk, additional verification recommended |
| `HIGH` | 60-79 | High risk, manual review required |
| `CRITICAL` | 80-100 | Critical risk, likely fraudulent |

## Configuration

Configuration is managed via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `ENVIRONMENT` | `dev` | Environment (dev, staging, prod) |
| `LOG_LEVEL` | `INFO` | Logging level (DEBUG, INFO, WARNING, ERROR) |
| `PORT` | `8080` | Application port |
| `KEY_VAULT_URL` | - | Azure Key Vault URL |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | - | Application Insights connection |
| `RISKSHIELD_API_URL` | - | RiskShield API endpoint |
| `RISKSHIELD_API_KEY` | - | RiskShield API key |
| `RISKSHIELD_API_TIMEOUT` | `30` | Request timeout in seconds |
| `RISKSHIELD_MAX_RETRIES` | `3` | Max retry attempts |
| `CORS_ORIGINS` | `["*"]` | Allowed CORS origins |
| `RATE_LIMIT_REQUESTS` | `100` | Max requests per minute |

## Development

### Project Structure

```
app/
├── src/
│   ├── api/
│   │   └── v1/
│   │       └── routes.py          # API endpoints
│   ├── core/
│   │   ├── config.py              # Configuration management
│   │   └── logging.py             # Structured logging
│   ├── models/
│   │   └── schemas.py             # Pydantic models
│   ├── services/
│   │   └── riskshield_client.py   # External API client
│   └── main.py                    # Application entry point
├── tests/
│   ├── unit/                      # Unit tests
│   ├── integration/               # Integration tests
│   └── conftest.py                # Test fixtures
├── Dockerfile                     # Container build
├── pyproject.toml                 # Project metadata
└── README.md                      # This file
```

### Running Tests

```bash
# Run all tests
uv run pytest

# Run with coverage
uv run pytest --cov=src --cov-report=html

# Run specific test file
uv run pytest tests/unit/test_models.py

# Run with verbose output
uv run pytest -v

# Run only unit tests
uv run pytest tests/unit/

# Run only integration tests
uv run pytest tests/integration/
```

### Code Quality

```bash
# Linting
uv run ruff check src/

# Format code
uv run ruff format src/

# Type checking
uv run mypy src/

# Security scanning
uv run bandit -r src/
```

### Adding a New Endpoint

1. Create route in `src/api/v1/routes.py`:

```python
@router.get("/example")
async def example_endpoint() -> dict:
    return {"message": "Hello"}
```

2. Add Pydantic models in `src/models/schemas.py`

3. Add tests in `tests/integration/test_api.py`

4. Update OpenAPI documentation

## Error Handling

The API uses standardized error codes:

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `VALIDATION_ERROR` | 400 | Invalid request data |
| `AUTHENTICATION_ERROR` | 401 | Authentication failed |
| `RATE_LIMIT_ERROR` | 429 | Rate limit exceeded |
| `UPSTREAM_ERROR` | 502/503 | Upstream service error |
| `TIMEOUT_ERROR` | 504 | Request timeout |
| `INTERNAL_ERROR` | 500 | Unexpected server error |

## Security

### Input Validation

- All inputs are validated using Pydantic models
- South African ID numbers are validated using:
  - Length check (13 digits)
  - Date portion validation (YYMMDD)
  - Luhn checksum algorithm

### Rate Limiting

- Default: 100 requests per minute per IP
- Configurable via `RATE_LIMIT_REQUESTS` environment variable
- Returns 429 status when exceeded

### Secret Management

- API keys stored in Azure Key Vault
- Never logged or exposed in error messages
- Automatic credential rotation via Azure Managed Identity

## Observability

### Logging

All logs are JSON-formatted with:

```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "level": "INFO",
  "message": "validation_request_completed",
  "correlation_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "risk_score": 72,
  "risk_level": "MEDIUM"
}
```

### Correlation IDs

Every request receives a unique correlation ID that:
- Is returned in the response
- Is included in all log entries
- Can be used to trace requests across services

### Application Insights

When `APPLICATIONINSIGHTS_CONNECTION_STRING` is set:
- Request telemetry is automatically collected
- Dependencies are tracked
- Exceptions are logged
- Custom metrics are available

## Troubleshooting

### Common Issues

**Port already in use:**
```bash
# Find process using port
lsof -i :8080
# Kill process
kill -9 <PID>
```

**Module not found:**
```bash
# Ensure virtual environment is activated
source .venv/bin/activate
# Reinstall dependencies
uv sync
```

**Key Vault access denied:**
```bash
# Login to Azure
az login
# Verify subscription
az account show
# Check Key Vault access
az keyvault secret list --vault-name <vault-name>
```

### Debug Mode

Enable debug logging:
```bash
export LOG_LEVEL=DEBUG
uv run uvicorn src.main:app --reload --port 8080
```

## License

Proprietary - For internal use only.

## Support

- **Documentation**: `/docs` endpoint
- **Issues**: Contact Platform Engineering team
- **Runbooks**: See `documentation/runbooks/` directory
