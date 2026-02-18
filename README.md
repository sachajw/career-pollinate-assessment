# FinRisk Platform - Applicant Validator

> **Technical Assessment Solution** for Pollinate Platform Engineering Role
>
> A secure, cloud-native service for loan applicant fraud risk validation.

## Project Overview

FinSure Capital requires a production-ready integration service to validate loan applicants through RiskShield's fraud detection API. This solution delivers a secure, scalable Azure-based platform using modern cloud-native patterns.

## Architecture

### High-Level Design

```
Loan System → API Gateway → Applicant Validator → RiskShield API
              (FinRisk)           (Domain Service)
                                    ↓
                            Azure Key Vault
                            Application Insights
                            Log Analytics
```

### Technology Stack

| Layer | Technology | Justification |
|-------|-----------|---------------|
| **Runtime** | Python 3.13 (FastAPI) | Async support, auto docs, Pydantic validation |
| **Container** | Docker (Python Slim) | Small footprint (~180MB), security |
| **Compute** | Azure Container Apps | Scale-to-zero, managed K8s, KEDA |
| **Registry** | Azure Container Registry | Native integration with Container Apps |
| **Secrets** | Azure Key Vault | Managed, audited, RBAC-based |
| **Identity** | Managed Identity | Password-less, Azure-native |
| **Logging** | Application Insights + Log Analytics | Full-stack APM, distributed tracing |
| **IaC** | Terraform | Multi-cloud, declarative, state management |
| **CI/CD** | Azure DevOps | Native integration, YAML pipelines |

### Deployed Environments

| Environment | Status | URL |
|-------------|--------|-----|
| **Dev** | ✅ Deployed | `https://finrisk-dev.pangarabbit.com` |
| **Prod** | 📋 Documented | Not deployed (Azure quota limits) |

### API Documentation Endpoints

**Azure (Direct)**
- Swagger UI: https://ca-finrisk-dev.icydune-b53581f6.eastus2.azurecontainerapps.io/docs
- ReDoc: https://ca-finrisk-dev.icydune-b53581f6.eastus2.azurecontainerapps.io/redoc

**Cloudflare (Custom Domain)**
- Swagger UI: https://finrisk-dev.pangarabbit.com/docs
- ReDoc: https://finrisk-dev.pangarabbit.com/redocs

### Documentation

| Document | Description |
|----------|-------------|
| [Technical Assessment](./documentation/technical-assessment.md) | Original assessment requirements |
| [Solution Architecture](./documentation/architecture/solution-architecture.md) | Complete architecture design |
| [Architecture Diagrams](./documentation/architecture/architecture-diagram.md) | Visual system representations |
| [Architecture Decisions](./documentation/adr/README.md) | ADRs for key decisions |
| [App README](./app/README.md) | Application-specific documentation |
| [Terraform README](./terraform/README.md) | Infrastructure documentation |
| [Pipeline README](./pipelines/README.md) | CI/CD documentation |

## Requirements Traceability

| Requirement | Implementation | Documentation |
|-------------|----------------|---------------|
| **1. Application Layer** | | |
| POST /validate endpoint | FastAPI route with Pydantic validation | [App README](./app/README.md) |
| Error handling | Exception handlers, structured error responses | [Solution Architecture](./documentation/architecture/solution-architecture.md) |
| Logging | Structured JSON logs with correlation IDs | [ADR-002](./documentation/adr/002-python-runtime.md) |
| Timeout handling | 30s timeout on external API calls | [Solution Architecture](./documentation/architecture/solution-architecture.md) |
| Retry logic | Exponential backoff (3 attempts) | [Solution Architecture](./documentation/architecture/solution-architecture.md) |
| Correlation IDs | UUID v4 for request tracing | [Solution Architecture](./documentation/architecture/solution-architecture.md) |
| **2. Containerisation** | | |
| Multi-stage builds | Dockerfile with builder/runtime stages | [App Dockerfile](./app/Dockerfile) |
| Non-root user | appuser:1001 | [ADR-005](./documentation/adr/005-docker-container-strategy.md) |
| Small base image | Python 3.13 Slim (~180MB) | [ADR-005](./documentation/adr/005-docker-container-strategy.md) |
| Healthcheck | /health and /ready endpoints | [App README](./app/README.md) |
| **3. Infrastructure as Code** | | |
| Resource Group | `rg-finrisk-dev` | [Terraform README](./terraform/README.md) |
| Container App | `ca-finrisk-dev` with scale-to-zero | [Container App Module](./terraform/modules/container-app/README.md) |
| Container Registry | ACR Basic tier | [Container Registry Module](./terraform/modules/container-registry/README.md) |
| Key Vault | `kv-finrisk-dev` with RBAC | [Key Vault Module](./terraform/modules/key-vault/README.md) |
| Log Analytics | `log-finrisk-dev`, 30-day retention | [Observability Module](./terraform/modules/observability/README.md) |
| Application Insights | Workspace-based | [Observability Module](./terraform/modules/observability/README.md) |
| Managed Identity | System-assigned on Container App | [ADR-003](./documentation/adr/003-managed-identity-security.md) |
| Role assignments | AcrPull, Key Vault Secrets User | [Terraform README](./terraform/README.md) |
| Remote state | Azure Storage backend | [Terraform README](./terraform/README.md) |
| Modules | 7 reusable modules | [Terraform Modules](./terraform/modules/) |
| Dev/Prod environments | Environment-specific configs | [Dev README](./terraform/environments/dev/README.md) |
| Naming conventions | `{type}-{project}-{env}` | [ADR-006](./documentation/adr/006-terraform-module-architecture.md) |
| No hardcoded secrets | Key Vault + Managed Identity | [ADR-003](./documentation/adr/003-managed-identity-security.md) |
| **4. Security** | | |
| API key in Key Vault | RISKSHIELD-API-KEY secret | [Key Vault Module](./terraform/modules/key-vault/README.md) |
| Managed Identity auth | System-assigned MI for all Azure access | [ADR-003](./documentation/adr/003-managed-identity-security.md) |
| HTTPS only | Ingress TLS enforced | [Solution Architecture](./documentation/architecture/solution-architecture.md) |
| Diagnostic logging | All resources → Log Analytics | [Observability Module](./terraform/modules/observability/README.md) |
| Threat modelling | MITM, credential theft, DDoS mitigations | [Solution Architecture](./documentation/architecture/solution-architecture.md) |
| Private endpoints (bonus) | Key Vault, ACR | [Private Endpoints Module](./terraform/modules/private-endpoints/README.md) |
| Azure AD auth (bonus) | EasyAuth on Container App | [ADR-008](./documentation/adr/008-bonus-security-enhancements.md) |
| Network restrictions (bonus) | IP allowlist, network ACLs | [ADR-008](./documentation/adr/008-bonus-security-enhancements.md) |
| **5. CI/CD Pipeline** | | |
| Build stage | Test, Docker build, Trivy scan, ACR push | [Pipeline README](./pipelines/README.md) |
| Infrastructure stage | Terraform init/plan/apply | [Pipeline README](./pipelines/README.md) |
| Deploy stage | Container App update, smoke test | [Pipeline README](./pipelines/README.md) |
| Service connections | Azure Resource Manager | [Terraform README](./terraform/README.md) |
| Variable groups | `finrisk-iac-tf-dev` | [Pipeline README](./pipelines/README.md) |
| Separate environments | Branch-based: `dev` → dev, `main` → prod | [Pipeline README](./pipelines/README.md) |

## Repository Structure

```
.
├── app/                          # Application code
│   ├── src/
│   │   ├── api/v1/             # FastAPI routes
│   │   ├── models/             # Pydantic models
│   │   ├── services/           # Business logic
│   │   ├── core/               # Config, logging
│   │   └── main.py             # Application entry point
│   ├── tests/                  # Unit, integration tests
│   ├── Dockerfile              # Multi-stage container build
│   ├── pyproject.toml          # Project metadata (uv)
│   └── README.md               # Application documentation
├── terraform/                  # Infrastructure as Code
│   ├── modules/                # Reusable Terraform modules
│   │   ├── container-app/
│   │   ├── container-registry/
│   │   ├── key-vault/
│   │   ├── networking/
│   │   ├── observability/
│   │   ├── private-endpoints/
│   │   └── resource-group/
│   ├── environments/           # Environment-specific configs
│   │   ├── dev/
│   │   └── prod/
│   └── README.md               # Terraform documentation
├── pipelines/                  # CI/CD definitions
│   ├── azure-pipelines-app.yml    # Application CI/CD pipeline
│   ├── azure-pipelines-infra.yml  # Infrastructure pipeline
│   └── README.md               # Pipeline documentation
├── documentation/              # Architecture documentation
│   ├── adr/                    # Architecture Decision Records
│   └── architecture/           # Solution architecture
│       ├── solution-architecture.md
│       └── architecture-diagram.md
└── README.md                   # This file
```

## Instructions to Run Locally

### Prerequisites

- Docker Desktop
- Python 3.13+ (for local development without Docker)
- uv (ultra-fast Python package installer)

### Using Docker (Recommended)

```bash
# Clone repository
git clone <repository-url>
cd carreer-pollinate-assessment

# Build container
docker build -t applicant-validator:local ./app

# Run container
docker run -p 8080:8080 applicant-validator:local

# Test the API
curl http://localhost:8080/health
curl -X POST http://localhost:8080/api/v1/validate \
  -H "Content-Type: application/json" \
  -d '{"firstName":"Jane","lastName":"Doe","idNumber":"9001011234088"}'
```

### Using Python (Development)

```bash
cd app

# Install uv (if not already installed)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Create virtual environment and install dependencies
uv sync

# Activate virtual environment
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Run locally with auto-reload
uv run uvicorn src.main:app --reload --port 8080

# Run tests
uv run pytest

# Type checking
uv run mypy src/

# Linting
uv run ruff check src/
```

### API Documentation

Auto-generated by FastAPI:
- **Swagger UI**: `http://localhost:8080/docs`
- **ReDoc**: `http://localhost:8080/redoc`

## Instructions to Deploy

### Prerequisites

- Azure subscription with Contributor access
- Azure CLI installed and authenticated (`az login`)
- Terraform 1.5+
- Azure DevOps project with service connections configured

### Step 1: Bootstrap Terraform State Storage (One-Time)

```bash
# Create resource group for Terraform state
az group create --name rg-terraform-state --location eastus2

# Create storage account
STORAGE="stfinrisktf$RANDOM"
az storage account create \
  --name $STORAGE \
  --resource-group rg-terraform-state \
  --sku Standard_LRS \
  --allow-blob-public-access false

# Create container
az storage container create --name tfstate --account-name $STORAGE

echo "Storage Account: $STORAGE"  # Save for variable group
```

### Step 2: Deploy Infrastructure

```bash
cd terraform/environments/dev

# Configure backend
cp backend.hcl.example backend.hcl
# Edit backend.hcl with your storage account name

# Initialize Terraform
terraform init -backend-config=backend.hcl

# Validate configuration
terraform validate

# Plan changes
terraform plan -out=tfplan

# Apply changes
terraform apply tfplan

# View outputs
terraform output
```

### Step 3: Configure Azure DevOps

1. **Service Connections**: Create `azure-service-connection` (Azure Resource Manager)
2. **Variable Group**: Create `finrisk-iac-tf-dev` with `terraformStateStorageAccount`
3. **Environments**: Create `finrisk-iac-tf-dev` and `finrisk-app-dev`

### Step 4: Run CI/CD Pipeline

Push to `dev` branch or manually trigger the pipelines in Azure DevOps:
1. Run `FinRisk-IaC-Terraform` pipeline first (infrastructure)
2. Run `FinRisk-App-CI-CD` pipeline (application)

See [terraform/README.md](./terraform/README.md) and [pipelines/README.md](./pipelines/README.md) for detailed instructions.

## Security Considerations

### Threat Model

| Threat | Mitigation |
|--------|-----------|
| API Key Exposure | Key Vault + Managed Identity (no env vars) |
| MITM Attacks | HTTPS only, TLS 1.2+ enforced |
| Credential Theft | No passwords, Managed Identity-based auth |
| DDoS | Azure DDoS protection + rate limiting |
| Injection Attacks | Input validation (Pydantic) |
| Dependency Vulnerabilities | Trivy container scanning |

### Security Features

- **Secrets Management**: All secrets stored in Azure Key Vault, accessed via Managed Identity
- **Network Security**: Private endpoints for Key Vault and ACR (bonus feature)
- **Identity**: System-assigned Managed Identity on Container App
- **Transport**: HTTPS enforced on all endpoints
- **Monitoring**: Diagnostic logging to Log Analytics for all resources
- **Container Security**: Non-root user, minimal base image, vulnerability scanning

See [ADR-003](./documentation/adr/003-managed-identity-security.md) and [ADR-008](./documentation/adr/008-bonus-security-enhancements.md) for detailed security analysis.

## Trade-offs Explained

### Why Azure Container Apps over App Service?

| Criteria | Container Apps | App Service | Decision |
|----------|---------------|-------------|----------|
| Cost | Pay per second, scale to zero | Always-on minimum cost | ✅ Container Apps |
| Scaling | KEDA event-driven | Basic autoscale | ✅ Container Apps |
| Complexity | Managed K8s abstraction | Simpler | ⚖️ Acceptable |
| Future | Dapr integration | Limited | ✅ Container Apps |

**Full analysis**: [ADR-001](./documentation/adr/001-azure-container-apps.md)

### Why Python + FastAPI over .NET/Go/Node.js?

| Criteria | Python/FastAPI | Alternatives | Decision |
|----------|---------------|--------------|----------|
| Development Speed | Fastest | Slower | ✅ Python |
| API Documentation | Auto-generated | Manual/Swagger | ✅ Python |
| Data Validation | Pydantic (best-in-class) | Good | ✅ Python |
| Performance | Good | Better | ⚖️ Acceptable |
| Team Familiarity | FinTech standard | Varied | ✅ Python |

**Full analysis**: [ADR-002](./documentation/adr/002-python-runtime.md)

### Why Terraform over Bicep?

| Criteria | Terraform | Bicep | Decision |
|----------|-----------|-------|----------|
| Multi-Cloud | Yes | Azure only | ✅ Terraform |
| Ecosystem | Large module library | Growing | ✅ Terraform |
| State Management | Built-in | Azure-only | ✅ Terraform |
| Azure Native | Good | Better | ⚖️ Acceptable |

**Full analysis**: [ADR-006](./documentation/adr/006-terraform-module-architecture.md)

### Why Managed Identity over Service Principals?

| Criteria | Managed Identity | Service Principal | Decision |
|----------|-----------------|-------------------|----------|
| Secret Management | None required | Credentials to manage | ✅ Managed Identity |
| Rotation | Automatic | Manual | ✅ Managed Identity |
| Audit Trail | Built-in | Limited | ✅ Managed Identity |
| Scope | Resource-level | Subscription-level | ✅ Managed Identity |

**Full analysis**: [ADR-003](./documentation/adr/003-managed-identity-security.md)

---

**Assessment Date:** February 2026
