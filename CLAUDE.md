# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**FinRisk Platform** - Fraud and risk validation service for loan applicants (Pollinate Platform Engineering Technical Assessment).

**DDD Naming Convention:**
- Project: `finrisk` (FinSure + Risk validation)
- Service: `applicant-validator` (domain capability)
- Resources: `rg-finrisk-dev`, `ca-finrisk-dev`, `kv-finrisk-dev`

## Development Commands

### Application

```bash
cd app

# Install uv (if not installed)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Install dependencies
uv sync

# Run dev server
uv run uvicorn src.main:app --reload --port 8080

# Run tests
uv run pytest

# Run specific test
uv run pytest tests/unit/test_models.py -v

# Lint and format
uv run ruff check src/
uv run ruff format src/

# Type check
uv run mypy src/

# Docker
docker build -t applicant-validator:local .
docker run -p 8080:8080 applicant-validator:local
```

### Terraform

```bash
cd terraform/environments/dev

# First-time setup
cp backend.hcl.example backend.hcl  # Edit with storage account name
cp terraform.tfvars.example terraform.tfvars

# Workflow
terraform init -backend-config=backend.hcl
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output
```

## Architecture

**Stack:** Python 3.13 + FastAPI, uv, Azure Container Apps, Key Vault, Managed Identity, Application Insights, Terraform, Azure DevOps

**Key ADRs:** `documentation/adr/`
- ADR-001: Azure Container Apps (scale-to-zero for cost savings)
- ADR-002: Python + FastAPI (auto OpenAPI, Pydantic validation)
- ADR-003: Managed Identity (zero secrets, SOC 2 compliant)
- ADR-005: Docker multi-stage builds (~180MB image)
- ADR-006: Terraform module architecture

## Application Structure

```
app/src/
  api/v1/routes.py      # POST /api/v1/validate, health endpoints
  models/validation.py  # Pydantic request/response models
  services/riskshield.py # RiskShield API client with resilience patterns
  core/
    config.py           # Settings via pydantic-settings
    secrets.py          # Key Vault integration
    middleware.py       # Correlation ID middleware
    logging.py          # Structured logging with structlog
app/tests/
  unit/                 # Unit tests for models, config
  integration/          # API integration tests
```

**Resilience Patterns** (in `services/riskshield.py`):
- Circuit breaker (trips after 5 failures, 60s recovery)
- Retry with exponential backoff (3 attempts)
- Timeouts: 5s connect, 10s read

## API Endpoints

FastAPI auto-docs: `/docs` (Swagger), `/redoc`

| Endpoint | Purpose |
|----------|---------|
| `POST /api/v1/validate` | Validate applicant risk |
| `GET /health` | Health check |
| `GET /ready` | Readiness probe |

## CI/CD Pipelines

| Pipeline | File | Stages |
|----------|------|--------|
| FinRisk-App-CI-CD | `pipelines/azure-pipelines-app.yml` | Test → Build → Deploy |
| FinRisk-IaC-Terraform | `pipelines/azure-pipelines-infra.yml` | Terraform plan/apply |

Branch strategy: `dev` → dev environment, `main` → prod

## Development Notes

- Secrets: All via Key Vault + Managed Identity (never env vars)
- Commits: Conventional (`feat:`, `fix:`, `docs:`, `chore:`)
- Test coverage: 80%+ target
- Container image: < 200MB
