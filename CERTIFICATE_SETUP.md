# Certificate Setup for finrisk.pangarabbit.com

## Overview

Your Cloudflare certificate will be installed in two simple steps:
1. **One-time upload** via Azure CLI (manual, done once)
2. **Terraform deployment** references the uploaded certificate

This approach keeps sensitive certificate data out of Terraform state and version control.

---

## Step 1: Deploy Infrastructure (Without Custom Domain)

First, deploy the base infrastructure:

```bash
cd terraform/environments/dev
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
```

This creates the Container App Environment where the certificate will be uploaded.

---

## Step 2: Upload Certificate (One-Time)

After the Container App Environment exists, upload your certificate:

```bash
# Automated script (recommended)
./scripts/upload-certificate.sh
```

**Manual upload (alternative):**
```bash
az containerapp env certificate upload \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --certificate-file /Users/tvl/Desktop/cloudflare-cert.pfx \
  --certificate-name finrisk-pangarabbit-cert \
  --password ""
```

**Verify upload:**
```bash
az containerapp env certificate list \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --output table
```

---

## Step 3: Enable Custom Domain in Terraform

Edit `terraform/environments/dev/terraform.tfvars`:

```hcl
# Enable custom domain
custom_domain_enabled = true
custom_domain_name    = "finrisk.pangarabbit.com"
certificate_name      = "finrisk-pangarabbit-cert"
```

**Or use environment variables:**
```bash
export TF_VAR_custom_domain_enabled=true
export TF_VAR_custom_domain_name="finrisk.pangarabbit.com"
export TF_VAR_certificate_name="finrisk-pangarabbit-cert"
```

---

## Step 4: Deploy with Custom Domain

```bash
# Automated script
./scripts/deploy-with-certificate.sh

# Or manually
cd terraform/environments/dev
terraform plan -out=tfplan
terraform apply tfplan
```

Get the outputs:
```bash
terraform output application_url
terraform output custom_domain_verification_id
```

---

## Step 5: Configure DNS (Cloudflare)

Add these records in your Cloudflare dashboard for `pangarabbit.com`:

### CNAME Record
```
Type:   CNAME
Name:   finrisk
Target: <container_app_fqdn>  # From terraform output
Proxy:  ✅ Enabled (orange cloud)
TTL:    Auto
```

### TXT Record (Domain Verification)
```
Type:    TXT
Name:    asuid.finrisk
Content: <verification_id>  # From terraform output
Proxy:   ⬜ DNS only (gray cloud)
TTL:     Auto
```

---

## Step 6: Configure Cloudflare SSL

1. Go to **SSL/TLS → Overview**
2. Set encryption mode to: **Full (strict)**
3. Verify Origin Server certificate is active

### Why Full (strict)?
- ✅ **Full (strict)**: Cloudflare validates your specific certificate
- ⚠️ **Full**: Accepts any valid certificate (less secure)
- ❌ **Flexible**: No encryption between Cloudflare and Azure (insecure)

---

## Verification

After DNS propagates (5-10 minutes):

```bash
# Test HTTPS connectivity
curl -I https://finrisk.pangarabbit.com/health

# Expected: HTTP/1.1 200 OK (or 404 if app not deployed yet)

# Check certificate details
echo | openssl s_client -connect finrisk.pangarabbit.com:443 \
  -servername finrisk.pangarabbit.com 2>/dev/null | \
  openssl x509 -noout -subject -dates

# Check DNS resolution
nslookup finrisk.pangarabbit.com
```

---

## Architecture Flow

```
┌──────────┐    HTTPS     ┌────────────┐    HTTPS     ┌──────────────────┐
│  Client  │ ──────────> │ Cloudflare │ ──────────> │  Azure Container │
│          │              │   Proxy    │              │       App        │
└──────────┘              └────────────┘              └──────────────────┘
                               │                              │
                         Universal SSL              Cloudflare Origin Cert
                         (Auto-managed)             (Uploaded via CLI)
```

**Traffic path:**
1. Client → Cloudflare (encrypted with Cloudflare Universal SSL)
2. Cloudflare → Azure (encrypted with your Cloudflare Origin Certificate)
3. Azure → Your app (internal, encrypted)

---

## Certificate Details

- **Type**: Cloudflare Origin Certificate
- **Domains**: `*.pangarabbit.com`, `pangarabbit.com`
- **Custom**: `finrisk.pangarabbit.com`
- **Issuer**: Cloudflare Origin CA
- **Valid**: 2026-02-15 to 2041-02-11 (15 years!)
- **File**: `/Users/tvl/Desktop/cloudflare-cert.pfx`

---

## Troubleshooting

### Certificate upload fails

**Error: "Container App Environment not found"**
```bash
# Deploy infrastructure first
cd terraform/environments/dev
terraform apply
```

**Error: "Certificate file not found"**
```bash
# Verify file location
ls -lh /Users/tvl/Desktop/cloudflare-cert.pfx

# Re-convert from PEM if needed
openssl pkcs12 -export -out /Users/tvl/Desktop/cloudflare-cert.pfx \
  -inkey /Users/tvl/Desktop/cloudflare-cert.pem \
  -in /Users/tvl/Desktop/cloudflare-cert.pem \
  -passout pass:
```

### Custom domain not working

**Check Terraform data source:**
```bash
cd terraform/environments/dev
terraform plan

# Should show: data.azurerm_container_app_environment_certificate.this will be read
```

**List uploaded certificates:**
```bash
az containerapp env certificate list \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev
```

**Check custom domain binding:**
```bash
az containerapp show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query "properties.configuration.ingress.customDomains"
```

### DNS not resolving

```bash
# Check DNS propagation
dig finrisk.pangarabbit.com
nslookup finrisk.pangarabbit.com

# Check via Cloudflare DNS
dig finrisk.pangarabbit.com @1.1.1.1
```

### 526 SSL handshake failed

1. Verify Cloudflare SSL mode: **Full (strict)**
2. Check certificate is uploaded to Azure
3. Verify certificate name matches in Terraform
4. Check certificate expiry date

---

## Re-uploading Certificate

If you need to replace the certificate:

```bash
# Delete existing certificate
az containerapp env certificate delete \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --certificate finrisk-pangarabbit-cert \
  --yes

# Upload new certificate
./scripts/upload-certificate.sh
```

**Note:** The script will prompt you to delete if it already exists.

---

## Security Notes

✅ **What's secure:**
- Certificate uploaded via Azure CLI (not in Terraform state)
- Certificate files in `.gitignore`
- No sensitive data in version control
- Managed by Azure RBAC

⚠️ **Important:**
- Certificate valid until **2041-02-11** (set reminder to rotate)
- Never commit `*.pfx`, `*.pem`, or `*.p12` files
- Backup certificate file securely (outside repo)

---

## Quick Reference Commands

```bash
# Upload certificate (once)
./scripts/upload-certificate.sh

# Deploy with custom domain
./scripts/deploy-with-certificate.sh

# Verify certificate
az containerapp env certificate list \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev

# Get outputs
cd terraform/environments/dev
terraform output application_url
terraform output custom_domain_verification_id

# Test HTTPS
curl -I https://finrisk.pangarabbit.com/health
```

---

## Files Changed

### Terraform Modules
- `terraform/modules/container-app/main.tf` - Uses `data` source instead of `resource`
- `terraform/modules/container-app/variables.tf` - Removed certificate blob variables
- `terraform/modules/container-app/outputs.tf` - References data source

### Environment Config
- `terraform/environments/dev/variables.tf` - Simplified certificate variable
- `terraform/environments/dev/main.tf` - References uploaded certificate

### Scripts
- `scripts/upload-certificate.sh` - One-time certificate upload
- `scripts/deploy-with-certificate.sh` - Deploy with custom domain

---

## Next Steps

1. ✅ Certificate converted (PEM → PFX)
2. ✅ Terraform configured (uses data source)
3. ⏳ Deploy base infrastructure
4. ⏳ Upload certificate via CLI
5. ⏳ Enable custom domain in Terraform
6. ⏳ Configure Cloudflare DNS
7. ⏳ Test HTTPS connectivity

---

## Resources

- [Azure Container Apps Custom Domains](https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-certificates)
- [Cloudflare Origin CA](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/)
- [Azure CLI Container Apps](https://learn.microsoft.com/en-us/cli/azure/containerapp/env/certificate)
