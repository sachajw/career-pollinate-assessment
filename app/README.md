# Applicant Validator API

**FinRisk Platform** - Loan Applicant Fraud Risk Validation Service

A FastAPI-based microservice that validates loan applicants against the RiskShield API for fraud risk assessment.

## Features

- **FastAPI** - Modern, fast Python API framework
- **Pydantic v2** - Data validation with type safety
- **Structured Logging** - JSON logs with correlation IDs
- **Health Probes** - Kubernetes-style liveness and readiness checks
- **Azure Integration** - Managed Identity, Key Vault, Application Insights
- **OpenAPI Docs** - Auto-generated interactive documentation

## Quick Start

### Prerequisites

- Python 3.13+
- [uv](https://github.com/astral-sh/uv) package manager

### Installation

```bash
# Install uv (if not already installed)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Install dependencies
uv sync

# Activate virtual environment
source .venv/bin/activate
```

### Run Locally

```bash
# Development server with auto-reload
uv run uvicorn src.main:app --reload --port 8080

# Or use the shorthand
uv run python -m src.main
```

Visit:
- API: http://localhost:8080
- Interactive docs: http://localhost:8080/docs
- Alternative docs: http://localhost:8080/redoc

### Run with Docker

```bash
# Build image
docker build -t applicant-validator:local .

# Run container
docker run -p 8080:8080 applicant-validator:local
```

## API Endpoints

### POST /api/v1/validate

Validate loan applicant for fraud risk.

**Request:**
```json
{
  "firstName": "Jane",
  "lastName": "Doe",
  "idNumber": "9001011234088"
}
```

**Response:**
```json
{
  "riskScore": 72,
  "riskLevel": "MEDIUM",
  "correlationId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

### GET /health

Liveness probe - checks if service is running.

### GET /ready

Readiness probe - checks if service is ready to handle requests.

## Development

See app/README.md for full development guide.

## License

Proprietary - FinSure Capital
