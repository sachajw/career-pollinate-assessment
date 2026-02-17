# Scripts

Automation scripts for FinRisk Platform deployment and certificate management.

## Directory Structure

```
scripts/
├── dev/                          # Development environment scripts
│   ├── upload-certificate.sh     # Upload cert to dev environment
│   └── deploy-with-certificate.sh # Deploy to dev with custom domain
├── prod/                         # Production environment scripts
│   ├── upload-certificate.sh     # Upload cert to prod environment
│   └── deploy-with-certificate.sh # Deploy to prod with custom domain
├── bootstrap-terraform-state.sh  # One-time setup of Terraform state
├── preflight-check.sh            # Validate prerequisites
├── setup-custom-certificate.sh   # Generic certificate tool (advanced)
└── README.md
```

---

## Bootstrap Scripts (Shared)

### bootstrap-terraform-state.sh

**Purpose**: One-time setup of Azure resources for Terraform remote state backend

**Usage**:
```bash
./bootstrap-terraform-state.sh [LOCATION]
```

**Prerequisites**:
- Azure CLI installed: `brew install azure-cli`
- Azure CLI authenticated: `az login`
- Correct subscription selected: `az account set --subscription <id>`

**What it creates**:
- Resource Group: `rg-terraform-state`
- Storage Account: `sttfstatefinrisk<random>`
- Blob Container: `tfstate`

**Output**: Configuration for `backend.hcl` files (dev and prod)

**When to run**: Once, before first Terraform deployment

---

### preflight-check.sh

**Purpose**: Validates prerequisites before Terraform deployment

**Usage**:
```bash
./preflight-check.sh
```

**What it checks**:
- Azure CLI installation & authentication
- Terraform installation (>= 1.5.0)
- Required Azure resource providers
- Subscription permissions
- Docker (optional)

---

## Environment Scripts

### Development

```bash
cd terraform/scripts/dev

# Upload certificate (one-time)
./upload-certificate.sh

# Deploy with custom domain
./deploy-with-certificate.sh
```

### Production

```bash
cd terraform/scripts/prod

# Upload certificate (one-time)
./upload-certificate.sh

# Deploy with custom domain
./deploy-with-certificate.sh
```

**Note**: Production scripts include an extra confirmation prompt before deployment.

---

## Workflow

### Development Environment

```bash
# 1. Bootstrap (one-time)
cd terraform/scripts
./bootstrap-terraform-state.sh eastus2

# 2. Configure and deploy infrastructure
cd ../environments/dev
cp backend.hcl.example backend.hcl
# Edit backend.hcl with values from bootstrap output
terraform init -backend-config=backend.hcl
terraform apply

# 3. Upload certificate (one-time)
cd ../scripts/dev
./upload-certificate.sh

# 4. Enable custom domain and deploy
export TF_VAR_custom_domain_enabled=true
export TF_VAR_custom_domain_name="finrisk.pangarabbit.com"
./deploy-with-certificate.sh

# 5. Configure DNS (see script output)
# 6. Set Cloudflare SSL to "Full (strict)"
```

### Production Environment

```bash
# 1. Configure and deploy infrastructure (uses same state storage as dev)
cd terraform/environments/prod
cp backend.hcl.example backend.hcl
# Edit backend.hcl with values from bootstrap output
terraform init -backend-config=backend.hcl
terraform apply

# 2. Upload certificate (one-time)
cd ../scripts/prod
./upload-certificate.sh

# 3. Enable custom domain and deploy
export TF_VAR_custom_domain_enabled=true
export TF_VAR_custom_domain_name="finrisk.pangarabbit.com"
./deploy-with-certificate.sh

# 4. Configure DNS (see script output)
```

### Updating Infrastructure

```bash
# Certificate already uploaded, just redeploy
cd terraform/scripts/dev   # or prod
./deploy-with-certificate.sh
```

### Rotating Certificate

```bash
# Delete old certificate
az containerapp env certificate delete \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --certificate finrisk-pangarabbit-cert \
  --yes

# Upload new certificate
cd terraform/scripts/dev
./upload-certificate.sh

# No Terraform changes needed - uses data source
```

---

## Configuration

Environment scripts use these defaults:

| Variable | Dev Default | Prod Default |
|----------|-------------|--------------|
| `RESOURCE_GROUP` | `rg-finrisk-dev` | `rg-finrisk-prod` |
| `ENVIRONMENT_NAME` | `cae-finrisk-dev` | `cae-finrisk-prod` |
| `CERT_FILE` | `/Users/tvl/Desktop/cloudflare-cert.pfx` | Same |
| `CERT_NAME` | `finrisk-pangarabbit-cert` | Same |
| `DOMAIN_NAME` | `finrisk.pangarabbit.com` | Same |

Override via environment variables:
```bash
CERT_FILE=/path/to/other.pfx ./upload-certificate.sh
```

---

## Troubleshooting

### Script won't execute

```bash
chmod +x dev/upload-certificate.sh
chmod +x prod/upload-certificate.sh
```

### Azure CLI not found

```bash
brew install azure-cli
```

### Not authenticated

```bash
az login
az account show  # Verify
```

### Certificate already exists

The upload script will prompt to delete and re-upload.

---

## Security Notes

- Scripts never commit certificates to Git
- Certificate uploaded via Azure CLI (not in Terraform state)
- Managed by Azure RBAC
- Files are in `.gitignore`
- Production scripts require explicit confirmation

---

## See Also

- [Terraform README](../README.md) - Main documentation with Azure DevOps setup
- [Dev Environment README](../environments/dev/README.md) - Dev-specific docs
- [Prod Environment README](../environments/prod/README.md) - Prod-specific docs
