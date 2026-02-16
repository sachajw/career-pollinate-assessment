# Scripts

Automation scripts for FinRisk Platform deployment and certificate management.

## Certificate Management

### upload-certificate.sh

**Purpose**: One-time upload of Cloudflare certificate to Azure Container App Environment

**Usage**:
```bash
./scripts/upload-certificate.sh
```

**Prerequisites**:
- Azure CLI installed and authenticated (`az login`)
- Container App Environment deployed (run Terraform first)
- Certificate file at: `/Users/tvl/Desktop/cloudflare-cert.pfx`

**What it does**:
1. Verifies Azure CLI authentication
2. Checks if Container App Environment exists
3. Uploads certificate to Azure
4. Displays next steps for DNS configuration

**When to run**: Once after initial infrastructure deployment

---

### deploy-with-certificate.sh

**Purpose**: Deploy Container App with custom domain enabled

**Usage**:
```bash
./scripts/deploy-with-certificate.sh
```

**Prerequisites**:
- Certificate uploaded via `upload-certificate.sh`
- Terraform initialized
- Custom domain enabled in `terraform.tfvars` or environment variables

**What it does**:
1. Runs `terraform plan` with custom domain configuration
2. Prompts for confirmation
3. Applies Terraform changes
4. Displays DNS configuration instructions

**When to run**: After certificate is uploaded, for initial setup and updates

---

### setup-custom-certificate.sh

**Purpose**: Generic certificate setup tool (advanced users)

**Usage**:
```bash
./scripts/setup-custom-certificate.sh --cert /path/to/cert.pem --domain api.example.com
```

**Features**:
- Converts PEM to PFX format
- Base64 encodes certificate
- Generates Terraform configuration
- Supports any domain (not just finrisk.pangarabbit.com)

---

## Workflow

### Initial Setup

```bash
# 1. Deploy infrastructure
cd terraform/environments/dev
terraform init -backend-config=backend.hcl
terraform apply

# 2. Upload certificate (one-time)
cd ../../../
./scripts/upload-certificate.sh

# 3. Enable custom domain
export TF_VAR_custom_domain_enabled=true
export TF_VAR_custom_domain_name="finrisk.pangarabbit.com"

# 4. Deploy with custom domain
./scripts/deploy-with-certificate.sh

# 5. Configure DNS (see output from script)
# 6. Set Cloudflare SSL to "Full (strict)"
```

### Updating Infrastructure

```bash
# Certificate is already uploaded, just deploy changes
./scripts/deploy-with-certificate.sh
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
./scripts/upload-certificate.sh

# No Terraform changes needed - uses data source
```

---

## Environment Variables

All scripts support these environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `CERT_FILE` | `/Users/tvl/Desktop/cloudflare-cert.pfx` | Path to certificate |
| `CERT_NAME` | `finrisk-pangarabbit-cert` | Certificate name in Azure |
| `RESOURCE_GROUP` | `rg-finrisk-dev` | Azure resource group |
| `ENVIRONMENT_NAME` | `cae-finrisk-dev` | Container App Environment name |
| `DOMAIN_NAME` | `finrisk.pangarabbit.com` | Custom domain |

---

## Troubleshooting

### Script won't execute

```bash
# Make executable
chmod +x scripts/upload-certificate.sh
chmod +x scripts/deploy-with-certificate.sh
```

### Azure CLI not found

```bash
# macOS
brew install azure-cli

# Or download from
# https://aka.ms/azure-cli
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

---

## See Also

- [CERTIFICATE_SETUP.md](../CERTIFICATE_SETUP.md) - Quick reference
- [Custom Domain Guide](../documentation/guides/custom-domain-certificate-setup.md) - Full guide
