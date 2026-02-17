# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains the solution for the **Pollinate Platform Engineering Technical Assessment** - the **FinRisk Platform** for FinSure Capital. The platform provides fraud and risk validation services for loan applicants.

**Key Components:**
- **Applicant Validator** - Domain service for loan applicant fraud risk validation (Python 3.13 + FastAPI)
- Azure Container Apps deployment with Managed Identity
- Infrastructure as Code (Terraform)
- CI/CD with Azure DevOps

**DDD Naming Convention:**
- Project: `finrisk` (FinSure + Risk validation context)
- Domain Service: `applicant-validator` (describes business capability)
- Resources: `rg-finrisk-dev`, `ca-finrisk-dev`, `kv-finrisk-dev`, etc.

## Development Commands

### Application (when app/ directory exists)

```bash
cd app

# Install uv package manager (if not installed)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Install dependencies and create virtual environment
uv sync

# Activate virtual environment
source .venv/bin/activate

# Run development server
uv run uvicorn src.main:app --reload --port 8080

# Run tests
uv run pytest

# Run specific test file
uv run pytest tests/unit/test_file.py

# Type checking
uv run mypy src/

# Linting
uv run ruff check src/

# Format code
uv run ruff format src/

# Build Docker image (DDD domain service name)
docker build -t applicant-validator:local .

# Run container locally
docker run -p 8080:8080 applicant-validator:local
```

### Terraform Infrastructure

```bash
cd terraform/environments/dev

# Initial setup (first time only)
cp backend.hcl.example backend.hcl
# Edit backend.hcl with your storage account name

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars as needed

# Initialize Terraform
terraform init -backend-config=backend.hcl

# Format code
terraform fmt -recursive

# Validate configuration
terraform validate

# Plan changes
terraform plan -out=tfplan

# Apply changes
terraform apply tfplan

# View outputs
terraform output

# Destroy infrastructure (caution!)
terraform destroy
```

## Architecture

### Technology Stack
- **Runtime**: Python 3.13 with FastAPI
- **Package Manager**: uv (10-100x faster than pip)
- **Compute**: Azure Container Apps (scale-to-zero for dev)
- **Secrets**: Azure Key Vault with Managed Identity
- **Observability**: Application Insights + Log Analytics
- **IaC**: Terraform 1.5+
- **CI/CD**: Azure DevOps YAML Pipelines

### Key Design Decisions
- **Azure Container Apps** over AKS/App Service: Scale-to-zero saves 50-70% cost in dev
- **Python + FastAPI** over Node.js: Rapid development, automatic OpenAPI docs, Pydantic validation
- **Managed Identity**: Zero secrets management, automatic token rotation, SOC 2 compliant
- **uv package manager**: 10-100x faster dependency resolution than pip

See `documentation/architecture/adr/` for detailed Architecture Decision Records.

## Repository Structure

```
app/                    # Application code (to be implemented)
  src/
    api/v1/            # FastAPI routes
    models/            # Pydantic models
    services/          # Business logic
    core/              # Config, logging
    main.py            # FastAPI app entry point
  tests/               # pytest tests
  Dockerfile           # Multi-stage container build
  pyproject.toml       # Project metadata (uv)

terraform/             # Infrastructure as Code
  modules/             # Reusable Terraform modules
    container-app/     # Azure Container Apps
    container-registry/# Azure Container Registry
    key-vault/         # Azure Key Vault
    observability/     # Log Analytics + App Insights
    resource-group/    # Resource group
  environments/
    dev/               # Development environment config

pipelines/             # CI/CD
  azure-pipelines.yml  # Main pipeline (Build -> Infrastructure -> Deploy -> Verify)

documentation/         # Architecture documentation
  architecture/
    solution-architecture.md
    adr/               # Architecture Decision Records
```

## API Specification

See `documentation/api/API_SPECIFICATION.md` for full API reference.

## CI/CD Pipeline Stages

1. **Build & Test**: Lint (Ruff), type check (mypy), unit tests (pytest), Docker build, Trivy scan
2. **Infrastructure**: Terraform plan/apply
3. **Deploy**: Update Container App with new image
4. **Verify**: Health checks, smoke tests

## Important Files

| File | Purpose |
|------|---------|
| `documentation/ARCHITECTURE_SUMMARY.md` | Quick reference architecture overview |
| `documentation/architecture/solution-architecture.md` | Complete architecture design |
| `documentation/architecture/adr/` | Architecture Decision Records |
| `terraform/README.md` | Terraform usage guide |
| `pipelines/README.md` | CI/CD pipeline documentation |

## Development Notes

- Follow conventional commits: `feat:`, `fix:`, `docs:`, `chore:`
- Target 80%+ test coverage
- All secrets go to Key Vault, never in code or environment variables
- Use Managed Identity for all Azure service authentication
- Container image target: < 200MB
