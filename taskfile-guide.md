# Taskfile Guide

This guide covers all available tasks for managing the FinRisk Platform development, deployment, and operations.

## Installation

```bash
# macOS
brew install go-task/tap/go-task

# Linux
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

# Verify
task --version
```

## Quick Reference

```bash
task                  # Show all available tasks
task --list           # Show tasks with descriptions
task <task>           # Run a specific task
task <task> --watch   # Run task on file changes
```

## Task Categories

### Infrastructure Tasks

| Task | Description |
|------|-------------|
| `infra:bootstrap` | Bootstrap Terraform state storage (one-time setup) |
| `infra:preflight` | Run pre-flight checks (Azure CLI, Terraform, providers) |
| `infra:init` | Initialize Terraform with backend |
| `infra:fmt` | Format Terraform files |
| `infra:validate` | Validate Terraform configuration |
| `infra:plan` | Plan infrastructure changes |
| `infra:apply` | Apply infrastructure changes |
| `infra:deploy` | Full infrastructure deployment workflow |
| `infra:destroy` | Destroy all infrastructure |
| `infra:output` | Show Terraform outputs |
| `infra:output-json` | Show Terraform outputs in JSON |
| `infra:clean` | Clean Terraform cache |
| `infra:status` | Show infrastructure deployment status |

**Common Workflow:**
```bash
# First time setup
task infra:bootstrap    # Create state storage
cp terraform/environments/dev/backend.hcl.example terraform/environments/dev/backend.hcl
# Edit backend.hcl with values from bootstrap output
cp terraform/environments/dev/terraform.tfvars.example terraform/environments/dev/terraform.tfvars

# Deploy infrastructure
task infra:deploy       # Full deployment with checks

# Or step by step
task infra:preflight    # Check prerequisites
task infra:init         # Initialize
task infra:plan         # Plan changes
task infra:apply        # Apply changes
```

### Application Tasks

| Task | Description |
|------|-------------|
| `app:install` | Install application dependencies (uv) |
| `app:run` | Run application locally on port 8080 |
| `app:test` | Run application tests |
| `app:test-watch` | Run tests in watch mode |
| `app:test-api` | Test /validate endpoint locally |
| `app:test-validate` | Test /validate endpoint on deployed app |
| `app:lint` | Run linters (ruff + mypy) |
| `app:format` | Format application code |
| `app:build` | Build Docker image |
| `app:push` | Push Docker image to ACR |
| `app:deploy` | Build, push, and update Container App |
| `app:clean` | Clean application build artifacts |

**Common Workflow:**
```bash
# Local development
task app:install        # Install dependencies
task app:run            # Start dev server
# In another terminal:
task app:test-api       # Test the API

# Before committing
task app:lint           # Run linters
task app:test           # Run tests

# Deploy to Azure
task app:deploy         # Build, push, deploy
```

### Security Tasks

| Task | Description |
|------|-------------|
| `kv:set-secret` | Set a secret in Azure Key Vault |
| `kv:get-secret` | Get a secret from Azure Key Vault |
| `kv:list-secrets` | List all secrets in Key Vault |
| `cert:upload` | Upload SSL certificate to Container App Environment |
| `cert:bind` | Bind custom domain to Container App |
| `cert:setup` | Full certificate setup (upload + bind) |

**Common Workflow:**
```bash
# Set the RiskShield API key
SECRET_NAME=RISKSHIELD-API-KEY SECRET_VALUE=your-api-key task kv:set-secret

# Setup custom domain certificate
CERT_FILE=/path/to/cert.pfx task cert:upload
task cert:bind

# Or do both at once
CERT_FILE=/path/to/cert.pfx task cert:setup
```

### Azure DevOps Tasks

| Task | Description |
|------|-------------|
| `ado:status` | Show Azure DevOps pipeline status |
| `ado:runs` | Show recent pipeline runs |
| `ado:run-infra` | Trigger infrastructure pipeline |
| `ado:run-app` | Trigger application pipeline |
| `ado:logs` | View logs for latest pipeline run |
| `ado:open` | Open Azure DevOps in browser |

**Prerequisites:**
```bash
# Install Azure DevOps extension
az extension add --name azure-devops

# Configure defaults
az devops configure --defaults \
  organization=https://dev.azure.com/<your-org> \
  project=<your-project>
```

**Common Workflow:**
```bash
task ado:status         # Check pipeline status
task ado:run-app        # Trigger app deployment
task ado:logs           # View deployment logs
```

### Monitoring & Operations Tasks

| Task | Description |
|------|-------------|
| `logs` | View Container App logs (live) |
| `urls` | Show deployed URLs |
| `test-endpoint` | Test deployed Container App endpoint |
| `smoke-test` | Run smoke tests against deployed application |
| `cost-estimate` | Show estimated monthly cost |
| `status` | Show overall platform status |

**Common Workflow:**
```bash
task urls               # Show all deployed URLs
task smoke-test         # Verify deployment is healthy
task logs               # Watch live logs
task cost-estimate      # Check monthly costs
```

### Utility Tasks

| Task | Description |
|------|-------------|
| `clean` | Clean all build artifacts and caches |
| `default` | Show all available tasks |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LOCATION` | `eastus2` | Azure region for resources |
| `CERT_FILE` | - | Path to SSL certificate (PFX) |
| `SECRET_NAME` | - | Key Vault secret name |
| `SECRET_VALUE` | - | Key Vault secret value |

## Deployed URLs

| Environment | URL |
|-------------|-----|
| **Custom Domain** | https://finrisk-dev.pangarabbit.com |
| **Default URL** | https://ca-finrisk-dev.icydune-b53581f6.eastus2.azurecontainerapps.io |

## Complete Workflows

### Initial Project Setup

```bash
# 1. Install Taskfile
brew install go-task/tap/go-task

# 2. Bootstrap infrastructure
task infra:bootstrap

# 3. Configure backend (use output from bootstrap)
cp terraform/environments/dev/backend.hcl.example terraform/environments/dev/backend.hcl
# Edit backend.hcl

# 4. Configure variables
cp terraform/environments/dev/terraform.tfvars.example terraform/environments/dev/terraform.tfvars
# Edit terraform.tfvars

# 5. Deploy infrastructure
task infra:deploy

# 6. Set API key secret
SECRET_NAME=RISKSHIELD-API-KEY SECRET_VALUE=your-key task kv:set-secret

# 7. Setup custom domain (optional)
CERT_FILE=/path/to/cert.pfx task cert:setup

# 8. Deploy application
task app:deploy

# 9. Verify deployment
task smoke-test
```

### Daily Development

```bash
# Start local development
task app:run

# In another terminal, test
task app:test-api

# Run tests
task app:test

# Lint and format
task app:lint
task app:format

# Commit and push (CI/CD handles deployment)
git add . && git commit -m "feat: new feature"
git push
```

### Production Deployment

```bash
# Check current status
task status

# Review costs
task cost-estimate

# Trigger production pipeline (if configured)
task ado:run-infra
task ado:run-app

# Monitor deployment
task ado:logs

# Verify after deployment
task smoke-test
```

### Troubleshooting

```bash
# Check infrastructure status
task infra:status

# View live logs
task logs

# Run smoke tests
task smoke-test

# Test specific endpoint
curl https://finrisk-dev.pangarabbit.com/health

# Check pipeline status
task ado:status
```

## Cost Reference

| Environment | Monthly Cost |
|-------------|--------------|
| **Development** | ~$8/month (scale-to-zero) |
| **Production** | ~$122/month (2 replicas) |

---

**See also:**
- [Main README](./README.md)
- [Terraform README](./terraform/README.md)
- [Pipeline README](./pipelines/README.md)
