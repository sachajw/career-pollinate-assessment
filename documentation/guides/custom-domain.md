# Custom Domain: finrisk.pangarabbit.com

**Status**: ✅ Live — https://finrisk.pangarabbit.com

This guide covers the full lifecycle of custom domain configuration for the FinRisk platform: certificate setup, DNS, Terraform, verification, and rotation.

---

## Current Configuration

| Item | Value |
|------|-------|
| **Custom Domain** | finrisk.pangarabbit.com |
| **Azure Container App** | ca-finrisk-dev |
| **Environment** | cae-finrisk-dev |
| **Resource Group** | rg-finrisk-dev |
| **Certificate Name** | finrisk-pangarabbit-cert |
| **Certificate Valid Until** | 2041-02-11 |
| **Azure FQDN** | ca-finrisk-dev.proudwater-4005d979.eastus2.azurecontainerapps.io |
| **Verification ID** | 7F9877DA54FDC73210D5C7D7F1776D6A757E6271FCEA153F3DDD87E9A3891299 |

### Architecture

```
Internet → Cloudflare (Universal SSL) → Azure Container App (Origin Certificate) → FastAPI App
```

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │ HTTPS (Cloudflare Universal SSL)
       ▼
┌─────────────────┐
│   Cloudflare    │
│  (CDN + DDoS +  │
│     WAF)        │
└────────┬────────┘
         │ HTTPS (Cloudflare Origin Certificate: finrisk-pangarabbit-cert)
         ▼
┌──────────────────────┐
│  Azure Container App │
│    (ca-finrisk-dev)  │
│  ┌────────────────┐  │
│  │    FastAPI     │  │
│  │  Port 8080     │  │
│  └────────────────┘  │
└──────────────────────┘
```

### Live Endpoints

| Endpoint | URL |
|----------|-----|
| Primary | https://finrisk.pangarabbit.com |
| API Docs | https://finrisk.pangarabbit.com/docs |
| Health Check | https://finrisk.pangarabbit.com/health |
| Direct Azure (bypass Cloudflare) | https://ca-finrisk-dev.proudwater-4005d979.eastus2.azurecontainerapps.io |

---

## Prerequisites

- Azure subscription with Contributor access
- Azure CLI installed and authenticated (`az account show`)
- Terraform 1.5+ installed
- Cloudflare account with DNS access for `pangarabbit.com`
- SSL certificate in PFX format (PKCS12) — see [Certificate Setup](#certificate-setup) below

---

## Certificate Setup

### Why this approach

Certificates are uploaded to Azure via CLI — not stored in Terraform state or version control. Terraform then references the uploaded certificate by name. This approach is:

- **Secure**: No sensitive data in `.tfstate` or Git
- **Simple**: One-time upload, then Terraform manages the reference
- **Auditable**: Azure RBAC controls who can upload/manage certificates

### Step 1: Prepare the certificate

Azure Container Apps require PFX (PKCS12) format. If you have a PEM certificate:

```bash
# Convert PEM to PFX (no password)
openssl pkcs12 -export \
  -out /path/to/cloudflare-cert.pfx \
  -inkey /path/to/cloudflare-cert.pem \
  -in /path/to/cloudflare-cert.pem \
  -passout pass:

# Verify conversion
openssl pkcs12 -in /path/to/cloudflare-cert.pfx -noout -password pass:
# Expected: MAC verified OK
```

**Certificate details for this deployment**:
- Type: Cloudflare Origin Certificate
- Domains: `*.pangarabbit.com`, `pangarabbit.com`
- Valid: 2026-02-15 to 2041-02-11 (15 years)

### Step 2: Deploy base infrastructure

The Container App Environment must exist before uploading the certificate:

```bash
cd terraform/environments/dev
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
```

### Step 3: Upload certificate (one-time)

```bash
# Automated script (recommended)
./scripts/upload-certificate.sh

# Manual upload
az containerapp env certificate upload \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --certificate-file /path/to/cloudflare-cert.pfx \
  --certificate-name finrisk-pangarabbit-cert \
  --password ""
```

**Verify upload**:

```bash
az containerapp env certificate list \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --output table
```

Expected output:
```
Name                      Subject                                    Thumbprint      ExpirationDate
------------------------  -----------------------------------------  --------------  -------------------
finrisk-pangarabbit-cert  CN=CloudFlare Origin Certificate, ...       D635DCCA...     2041-02-11T20:16:00
```

---

## DNS Configuration (Cloudflare)

### Step 1: Get the verification ID

```bash
az containerapp env show \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query "properties.customDomainConfiguration.customDomainVerificationId" \
  --output tsv
```

### Step 2: Add DNS records in Cloudflare

Navigate to **dash.cloudflare.com → pangarabbit.com → DNS → Records**.

**CNAME Record** (traffic routing):

| Field | Value |
|-------|-------|
| Type | CNAME |
| Name | finrisk |
| Target | ca-finrisk-dev.proudwater-4005d979.eastus2.azurecontainerapps.io |
| Proxy status | ✅ Proxied (Orange cloud) |
| TTL | Auto |

> Proxied enables Cloudflare's DDoS protection, CDN, WAF, and hides origin IP.

**TXT Record** (domain verification):

| Field | Value |
|-------|-------|
| Type | TXT |
| Name | asuid.finrisk |
| Content | 7F9877DA54FDC73210D5C7D7F1776D6A757E6271FCEA153F3DDD87E9A3891299 |
| Proxy status | ⬜ DNS only (Gray cloud) |
| TTL | Auto |

> Must be DNS only — Azure verifies this record directly; proxying blocks verification.

### Step 3: Configure Cloudflare SSL mode

In **Cloudflare → SSL/TLS → Overview**, set encryption mode to **Full (strict)**.

| Mode | Security | Description |
|------|----------|-------------|
| Flexible | Low | Only client → Cloudflare encrypted |
| Full | Medium | End-to-end encrypted, certificate not validated |
| **Full (strict)** | **High** | End-to-end encrypted + certificate validation |

### Step 4: Bind custom domain

After DNS propagation (usually 5–10 min):

```bash
az containerapp hostname bind \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --hostname finrisk.pangarabbit.com \
  --certificate finrisk-pangarabbit-cert \
  --environment cae-finrisk-dev
```

---

## Terraform Configuration

Terraform references the pre-uploaded certificate via a data source. No certificate data is stored in state.

### Module variables (`terraform/modules/container-app/variables.tf`)

```hcl
variable "custom_domain_enabled" {
  description = "Enable custom domain with certificate"
  type        = bool
  default     = false
}

variable "custom_domain_name" {
  description = "Custom domain name (e.g., finrisk.pangarabbit.com)"
  type        = string
  default     = ""
}

variable "certificate_name" {
  description = "Name of existing certificate uploaded via Azure CLI"
  type        = string
  default     = ""
}
```

### Data source (`terraform/modules/container-app/main.tf`)

```hcl
data "azurerm_container_app_environment_certificate" "this" {
  count = var.custom_domain_enabled ? 1 : 0

  name                         = var.certificate_name
  container_app_environment_id = azurerm_container_app_environment.this.id
}
```

### Ingress binding (`terraform/modules/container-app/main.tf`)

```hcl
ingress {
  # ... existing ingress configuration ...

  dynamic "custom_domain" {
    for_each = var.custom_domain_enabled ? [1] : []
    content {
      name           = var.custom_domain_name
      certificate_id = data.azurerm_container_app_environment_certificate.this[0].id
    }
  }
}
```

### Environment config (`terraform/environments/dev/terraform.tfvars`)

```hcl
custom_domain_enabled = true
custom_domain_name    = "finrisk.pangarabbit.com"
certificate_name      = "finrisk-pangarabbit-cert"
```

Or via environment variables:

```bash
export TF_VAR_custom_domain_enabled=true
export TF_VAR_custom_domain_name="finrisk.pangarabbit.com"
export TF_VAR_certificate_name="finrisk-pangarabbit-cert"
```

### Outputs (`terraform/modules/container-app/outputs.tf`)

```hcl
output "custom_domain_verification_id" {
  description = "Domain verification ID for custom domain setup"
  value       = azurerm_container_app_environment.this.custom_domain_verification_id
}
```

```bash
terraform output application_url
terraform output custom_domain_verification_id
```

---

## Verification & Testing

### DNS resolution

```bash
# CNAME record
nslookup finrisk.pangarabbit.com
# Expected: Returns Cloudflare IPs (172.67.x.x / 104.21.x.x)

# TXT record
nslookup -type=TXT asuid.finrisk.pangarabbit.com
# Expected: Returns the verification ID string

# Via Cloudflare DNS directly
dig finrisk.pangarabbit.com @1.1.1.1
```

### HTTPS connectivity

```bash
# HTTP status
curl -I https://finrisk.pangarabbit.com/
# Expected: HTTP/2 200, server: cloudflare

# Application response
curl https://finrisk.pangarabbit.com/
# Expected: {"service":"Applicant Validator API","version":"0.1.0","docs":"/docs"}

# Health check
curl https://finrisk.pangarabbit.com/health
# Expected: {"status":"healthy","version":"0.1.0","environment":"dev"}
```

### Certificate chain

```bash
echo | openssl s_client -connect finrisk.pangarabbit.com:443 \
  -servername finrisk.pangarabbit.com 2>/dev/null | \
  openssl x509 -noout -subject -issuer -dates
```

> Note: This shows Cloudflare's Universal SSL certificate (client-facing), not the Cloudflare Origin Certificate used between Cloudflare and Azure.

### Certificate status in Azure

```bash
az containerapp env certificate list \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query "[].{Name:name, Valid:properties.valid, Expires:properties.expirationDate}"
```

### Custom domain binding

```bash
az containerapp show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query "properties.configuration.ingress.customDomains"
```

---

## Certificate Rotation

The current certificate is valid until **2041-02-11**. Set a reminder for 2040.

When rotation is needed:

```bash
# 1. Generate new Cloudflare Origin Certificate (in Cloudflare dashboard)

# 2. Convert to PFX
openssl pkcs12 -export \
  -out new-cert.pfx \
  -inkey new-cert.pem \
  -in new-cert.pem \
  -passout pass:

# 3. Delete old certificate
az containerapp env certificate delete \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --certificate finrisk-pangarabbit-cert \
  --yes

# 4. Upload new certificate (same name)
az containerapp env certificate upload \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --certificate-file new-cert.pfx \
  --certificate-name finrisk-pangarabbit-cert \
  --password ""

# 5. Re-bind domain if needed
az containerapp hostname bind \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --hostname finrisk.pangarabbit.com \
  --certificate finrisk-pangarabbit-cert \
  --environment cae-finrisk-dev
```

---

## Troubleshooting

### DNS not resolving

```bash
dig finrisk.pangarabbit.com
dig TXT asuid.finrisk.pangarabbit.com
# If no results: wait for propagation (up to 24h, usually 5-10 min)
# macOS: sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
```

### 526 Invalid SSL certificate

1. Verify Cloudflare SSL mode: **Full (strict)**
2. Check certificate is uploaded to Azure (see Verification section)
3. Verify certificate name matches in Terraform config
4. Confirm certificate has not expired

### TXT record not found (binding fails)

```bash
# Verify TXT record exists
dig TXT asuid.finrisk.pangarabbit.com
# Must be "DNS only" (gray cloud) — not proxied
```

### Certificate upload fails

```bash
# Error: "Certificate file not found"
ls -lh /path/to/cloudflare-cert.pfx

# Error: "Invalid certificate format" — verify and re-convert
file /path/to/cloudflare-cert.pfx              # Should show: "data" or "PKCS #12"
openssl pkcs12 -in cloudflare-cert.pfx -noout -password pass:  # Should show: MAC verified OK

# Re-convert from PEM
openssl pkcs12 -export \
  -out cloudflare-cert.pfx \
  -inkey cloudflare-cert.pem \
  -in cloudflare-cert.pem \
  -passout pass:
```

### Application not responding

```bash
# Check container app status
az containerapp show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query "properties.runningStatus"

# View recent logs
az containerapp logs show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --tail 50

# Test direct Azure endpoint (bypass Cloudflare)
curl https://ca-finrisk-dev.proudwater-4005d979.eastus2.azurecontainerapps.io/health
```

### Custom domain not found in Terraform data source

```bash
cd terraform/environments/dev
terraform plan
# Should show: data.azurerm_container_app_environment_certificate.this will be read

# List uploaded certificates
az containerapp env certificate list \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev
```

---

## Security Checklist

- [x] Certificate uploaded via Azure CLI (not in Terraform state)
- [x] Certificate files in `.gitignore` (`*.pfx`, `*.pem`, `*.p12`)
- [x] Cloudflare SSL mode set to "Full (strict)"
- [x] DNS TXT record configured for domain verification
- [x] CNAME proxied through Cloudflare (DDoS protection)
- [x] HTTPS enforced (no HTTP access)
- [x] Certificate valid until 2041-02-11 (calendar reminder set for 2040)

---

## Related

- `terraform/environments/dev/DNS_CONFIGURATION.md` — current DNS record values
- `scripts/upload-certificate.sh` — automated certificate upload
- `scripts/verify-custom-domain.sh` — end-to-end verification script
- `scripts/deploy-with-certificate.sh` — deploy with custom domain enabled

## References

- [Azure Container Apps Custom Domains](https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-certificates)
- [Cloudflare Origin CA](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/)
- [Azure CLI: containerapp env certificate](https://learn.microsoft.com/en-us/cli/azure/containerapp/env/certificate)
- [Terraform: azurerm_container_app_environment_certificate](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app_environment_certificate)
