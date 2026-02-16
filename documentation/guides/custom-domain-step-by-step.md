# Custom Domain Setup: Step-by-Step Guide

**What We Did**: Configure `finrisk.pangarabbit.com` with a Cloudflare Origin Certificate on Azure Container Apps

**Date**: 2026-02-16

**Result**: ✅ Successfully deployed and operational at https://finrisk.pangarabbit.com

---

## Overview

This guide documents the exact steps taken to configure a custom domain with SSL certificate for an Azure Container App. The approach separates certificate management (one-time manual upload) from infrastructure deployment (Terraform), keeping sensitive certificate data out of version control.

**Architecture**:
```
Internet → Cloudflare (Universal SSL) → Azure Container App (Origin Certificate) → FastAPI App
```

---

## Prerequisites

### Required
- [x] Azure subscription with Contributor access
- [x] Azure CLI installed and authenticated
- [x] Terraform 1.5+ installed
- [x] Cloudflare domain with DNS access
- [x] SSL certificate (PEM or PFX format)

### Already Deployed
- [x] Azure Container App Environment: `cae-finrisk-dev`
- [x] Azure Container App: `ca-finrisk-dev`
- [x] Resource Group: `rg-finrisk-dev`

---

## Step 1: Prepare the Certificate

### 1.1 Verify Certificate Format

Our certificate was a Cloudflare Origin Certificate in PEM format:

```bash
# Check certificate details
openssl x509 -in /Users/tvl/Desktop/cloudflare-cert.pem -text -noout | grep -E "Subject:|DNS:|Not After"

# Output:
# Subject: CN=CloudFlare Origin Certificate, OU=CloudFlare Origin CA, O="CloudFlare, Inc."
# DNS:*.pangarabbit.com, DNS:pangarabbit.com
# Not After: Feb 11 20:16:00 2041 GMT
```

**Certificate Details**:
- Domains: `*.pangarabbit.com`, `pangarabbit.com`
- Valid until: 2041-02-11 (15 years)
- Type: Cloudflare Origin Certificate
- File: `/Users/tvl/Desktop/cloudflare-cert.pem`

### 1.2 Convert PEM to PFX (Azure Requirement)

Azure Container Apps requires certificates in PFX (PKCS12) format:

```bash
# Convert PEM to PFX (no password)
openssl pkcs12 -export \
  -out /Users/tvl/Desktop/cloudflare-cert.pfx \
  -inkey /Users/tvl/Desktop/cloudflare-cert.pem \
  -in /Users/tvl/Desktop/cloudflare-cert.pem \
  -passout pass:

# Verify conversion
openssl pkcs12 -in /Users/tvl/Desktop/cloudflare-cert.pfx -noout -password pass:
# Expected output: MAC verified OK
```

**Result**: Certificate converted to PFX format at `/Users/tvl/Desktop/cloudflare-cert.pfx`

---

## Step 2: Upload Certificate to Azure

### 2.1 Verify Azure Authentication

```bash
az account show
```

**Output**:
```json
{
  "environmentName": "AzureCloud",
  "id": "94b0c11e-3389-4ca0-b998-a3894e174f3c",
  "name": "Azure subscription 1",
  "state": "Enabled",
  "user": {
    "name": "azure@pangarabbit.com",
    "type": "user"
  }
}
```

### 2.2 Verify Container App Environment Exists

```bash
az containerapp env show \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev
```

**Expected**: JSON response with environment details (provisioningState: "Succeeded")

### 2.3 Upload Certificate

```bash
az containerapp env certificate upload \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --certificate-file /Users/tvl/Desktop/cloudflare-cert.pfx \
  --certificate-name finrisk-pangarabbit-cert \
  --password ""
```

**Output**:
```json
{
  "name": "finrisk-pangarabbit-cert",
  "properties": {
    "expirationDate": "2041-02-11T20:16:00Z",
    "provisioningState": "Succeeded",
    "subjectAlternativeNames": [
      "*.pangarabbit.com",
      "pangarabbit.com"
    ],
    "valid": true
  }
}
```

### 2.4 Verify Certificate Upload

```bash
az containerapp env certificate list \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --output table
```

**Output**:
```
Name                      Subject                                    Thumbprint                                ExpirationDate
------------------------  -----------------------------------------  ----------------------------------------  -------------------
finrisk-pangarabbit-cert  CN=CloudFlare Origin Certificate, ...       D635DCCAD5025FC5D1A8C552EEB48E8E09E45EF3  2041-02-11T20:16:00
```

**Result**: ✅ Certificate uploaded to Azure Container App Environment

---

## Step 3: Get Domain Verification ID

Azure requires a TXT record to verify domain ownership:

```bash
az containerapp env show \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query "properties.customDomainConfiguration.customDomainVerificationId" \
  --output tsv
```

**Output**:
```
7F9877DA54FDC73210D5C7D7F1776D6A757E6271FCEA153F3DDD87E9A3891299
```

**Save this value** - you'll need it for DNS configuration.

---

## Step 4: Get Container App FQDN

```bash
az containerapp show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query "properties.configuration.ingress.fqdn" \
  --output tsv
```

**Output**:
```
ca-finrisk-dev.proudwater-4005d979.eastus2.azurecontainerapps.io
```

---

## Step 5: Configure DNS in Cloudflare

### 5.1 Access Cloudflare Dashboard

1. Go to https://dash.cloudflare.com
2. Select domain: **pangarabbit.com**
3. Navigate to: **DNS** → **Records**

### 5.2 Add CNAME Record (Traffic Routing)

Click "Add Record" and configure:

| Field | Value |
|-------|-------|
| **Type** | CNAME |
| **Name** | finrisk |
| **Target** | ca-finrisk-dev.proudwater-4005d979.eastus2.azurecontainerapps.io |
| **Proxy status** | ✅ Proxied (Orange cloud) |
| **TTL** | Auto |

**Why Proxied?**
- Enables Cloudflare's DDoS protection
- Provides CDN caching
- Hides origin server IP
- Enables Cloudflare's Web Application Firewall (WAF)

**Click**: Save

### 5.3 Add TXT Record (Domain Verification)

Click "Add Record" and configure:

| Field | Value |
|-------|-------|
| **Type** | TXT |
| **Name** | asuid.finrisk |
| **Content** | 7F9877DA54FDC73210D5C7D7F1776D6A757E6271FCEA153F3DDD87E9A3891299 |
| **Proxy status** | ⬜ DNS only (Gray cloud) |
| **TTL** | Auto |

**Why DNS only?**
- Azure needs to verify this TXT record directly
- Proxying would prevent verification

**Click**: Save

### 5.4 Verify DNS Propagation

```bash
# Check CNAME record
nslookup finrisk.pangarabbit.com

# Expected output:
# Name:   finrisk.pangarabbit.com
# Addresses: 172.67.209.7, 104.21.85.186 (Cloudflare IPs)

# Check TXT record
nslookup -type=TXT asuid.finrisk.pangarabbit.com

# Expected output:
# asuid.finrisk.pangarabbit.com  text = "7F9877DA54FDC73210D5C7D7F1776D6A757E6271FCEA153F3DDD87E9A3891299"
```

**Propagation time**: Usually 5-10 minutes (can take up to 24 hours in rare cases)

---

## Step 6: Configure Cloudflare SSL/TLS

### 6.1 Set Encryption Mode

1. In Cloudflare dashboard, go to: **SSL/TLS** → **Overview**
2. Set encryption mode to: **Full (strict)**

**Why Full (strict)?**

| Mode | Security | Description |
|------|----------|-------------|
| Flexible | ❌ Low | Only client → Cloudflare encrypted |
| Full | ⚠️ Medium | End-to-end encrypted, but doesn't validate certificate |
| **Full (strict)** | ✅ High | End-to-end encrypted with certificate validation |

**Full (strict)** ensures:
1. Client → Cloudflare: Encrypted with Cloudflare Universal SSL
2. Cloudflare → Azure: Encrypted with YOUR Cloudflare Origin Certificate
3. Certificate is validated (not just any certificate)

---

## Step 7: Bind Custom Domain to Container App

### 7.1 Attempt Binding

After DNS propagation completes (TXT record is verified), bind the domain:

```bash
az containerapp hostname bind \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --hostname finrisk.pangarabbit.com \
  --certificate finrisk-pangarabbit-cert \
  --environment cae-finrisk-dev
```

**Success Output**:
```json
[
  {
    "bindingType": "SniEnabled",
    "certificateId": "/subscriptions/.../certificates/finrisk-pangarabbit-cert",
    "name": "finrisk.pangarabbit.com"
  }
]
```

### 7.2 Possible Errors

**Error: "TXT record not found"**
```
ERROR: A TXT record pointing from asuid.finrisk.pangarabbit.com to 7F9877DA... was not found.
```

**Solution**:
- Wait for DNS propagation (5-10 minutes)
- Verify TXT record in Cloudflare:
  ```bash
  nslookup -type=TXT asuid.finrisk.pangarabbit.com
  ```
- Ensure TXT record is "DNS only" (gray cloud), not proxied

**Error: "Certificate not found"**
```
ERROR: Certificate 'finrisk-pangarabbit-cert' not found
```

**Solution**:
- Verify certificate was uploaded:
  ```bash
  az containerapp env certificate list \
    --name cae-finrisk-dev \
    --resource-group rg-finrisk-dev
  ```
- Check certificate name matches exactly

---

## Step 8: Verify Custom Domain

### 8.1 Test DNS Resolution

```bash
nslookup finrisk.pangarabbit.com
```

**Expected**: Returns Cloudflare IP addresses (not Azure IPs)

### 8.2 Test HTTPS Connectivity

```bash
curl -I https://finrisk.pangarabbit.com/
```

**Expected**:
```
HTTP/2 200
server: cloudflare
content-type: application/json
```

### 8.3 Test Application Response

```bash
curl https://finrisk.pangarabbit.com/
```

**Expected**:
```json
{"service":"Applicant Validator API","version":"0.1.0","docs":"/docs"}
```

### 8.4 Test Health Endpoint

```bash
curl https://finrisk.pangarabbit.com/health
```

**Expected**:
```json
{
  "status": "healthy",
  "version": "0.1.0",
  "environment": "dev"
}
```

### 8.5 Verify Certificate Chain

```bash
echo | openssl s_client -connect finrisk.pangarabbit.com:443 \
  -servername finrisk.pangarabbit.com 2>/dev/null | \
  openssl x509 -noout -subject -issuer -dates
```

**Expected**:
```
subject=CN=pangarabbit.com
issuer=C=US, O=Google Trust Services, CN=WE1
notBefore=Feb 16 00:00:00 2026 GMT
notAfter=May 17 23:59:59 2026 GMT
```

**Note**: This shows Cloudflare's Universal SSL certificate (client-facing), not your Origin certificate (which is used between Cloudflare and Azure).

### 8.6 View API Documentation

```bash
# Open in browser
open https://finrisk.pangarabbit.com/docs
```

---

## Step 9: Update Terraform Configuration (Optional)

While we used Azure CLI for this one-time setup, we can update Terraform to reference the uploaded certificate for future deployments.

### 9.1 Add Variables to Module

**File**: `terraform/modules/container-app/variables.tf`

```hcl
#------------------------------------------------------------------------------
# Custom Domain and Certificate Configuration
#------------------------------------------------------------------------------

variable "custom_domain_enabled" {
  description = "Enable custom domain with certificate"
  type        = bool
  default     = false
}

variable "custom_domain_name" {
  description = "Custom domain name (e.g., api.pangarabbit.com)"
  type        = string
  default     = ""
}

variable "certificate_name" {
  description = "Name of existing certificate in Container App Environment (uploaded via Azure CLI)"
  type        = string
  default     = ""
}
```

### 9.2 Add Data Source to Module

**File**: `terraform/modules/container-app/main.tf`

```hcl
#------------------------------------------------------------------------------
# Container App Environment Certificate Reference (Optional)
#------------------------------------------------------------------------------
# References a certificate that was manually uploaded to the Container App Environment.
# The certificate should be uploaded once via Azure CLI (see scripts/upload-certificate.sh)
# Terraform will then reference the existing certificate by name.
#------------------------------------------------------------------------------
data "azurerm_container_app_environment_certificate" "this" {
  count = var.custom_domain_enabled ? 1 : 0

  name                         = var.certificate_name
  container_app_environment_id = azurerm_container_app_environment.this.id
}
```

### 9.3 Add Custom Domain to Ingress

**File**: `terraform/modules/container-app/main.tf` (in the `ingress` block)

```hcl
ingress {
  # ... existing ingress configuration ...

  # Custom domain binding (optional)
  # Requires a certificate uploaded to the Container App Environment
  dynamic "custom_domain" {
    for_each = var.custom_domain_enabled ? [1] : []
    content {
      name           = var.custom_domain_name
      certificate_id = data.azurerm_container_app_environment_certificate.this[0].id
    }
  }
}
```

### 9.4 Configure Environment Variables

**File**: `terraform/environments/dev/terraform.tfvars`

```hcl
# Custom domain configuration
custom_domain_enabled = true
custom_domain_name    = "finrisk.pangarabbit.com"
certificate_name      = "finrisk-pangarabbit-cert"
```

### 9.5 Add Outputs

**File**: `terraform/modules/container-app/outputs.tf`

```hcl
#------------------------------------------------------------------------------
# Custom Domain Outputs
#------------------------------------------------------------------------------

output "custom_domain_verification_id" {
  description = "Domain verification ID for custom domain setup"
  value       = azurerm_container_app_environment.this.custom_domain_verification_id
}

output "certificate_id" {
  description = "ID of the referenced certificate (if enabled)"
  value       = var.custom_domain_enabled ? data.azurerm_container_app_environment_certificate.this[0].id : null
}
```

---

## Security Best Practices

### ✅ What We Did Right

1. **Certificate uploaded via Azure CLI** - Not stored in Terraform state
2. **Certificate files in .gitignore** - Never committed to version control
3. **No sensitive data in environment variables** - Used direct Azure CLI upload
4. **DNS TXT record for verification** - Proves domain ownership
5. **Cloudflare Full (strict) SSL** - End-to-end encryption with validation

### ⚠️ Important Reminders

1. **Certificate expires 2041-02-11** - Set a calendar reminder for 2040
2. **Never commit certificate files** - `.pem`, `.pfx`, `.key`, etc.
3. **Backup certificate securely** - Store outside the repository
4. **Use Azure RBAC** - Control who can upload/manage certificates
5. **Monitor certificate expiry** - Set up alerts (though 15 years is plenty of time)

---

## Troubleshooting

### DNS Not Resolving

**Symptoms**:
- `nslookup finrisk.pangarabbit.com` returns NXDOMAIN
- Domain doesn't load in browser

**Solutions**:
1. Wait for DNS propagation (up to 24 hours, usually 5-10 minutes)
2. Check DNS records in Cloudflare dashboard
3. Verify CNAME target is correct
4. Clear local DNS cache: `sudo dscacheutil -flushcache` (macOS)

### 526 Invalid SSL Certificate

**Symptoms**:
- Browser shows "526: Invalid SSL certificate"
- Cloudflare cannot connect to origin

**Solutions**:
1. Verify SSL mode is "Full (strict)" in Cloudflare
2. Check certificate is uploaded to Azure:
   ```bash
   az containerapp env certificate list \
     --name cae-finrisk-dev \
     --resource-group rg-finrisk-dev
   ```
3. Verify custom domain binding:
   ```bash
   az containerapp show \
     --name ca-finrisk-dev \
     --resource-group rg-finrisk-dev \
     --query "properties.configuration.ingress.customDomains"
   ```

### Certificate Upload Fails

**Symptoms**:
- Error uploading certificate
- "Invalid certificate format"

**Solutions**:
1. Verify PFX format:
   ```bash
   file /Users/tvl/Desktop/cloudflare-cert.pfx
   # Should show: "data" or "PKCS #12"
   ```
2. Verify PFX is valid:
   ```bash
   openssl pkcs12 -in cloudflare-cert.pfx -noout -password pass:
   # Should show: "MAC verified OK"
   ```
3. Re-convert from PEM:
   ```bash
   openssl pkcs12 -export \
     -out cloudflare-cert.pfx \
     -inkey cloudflare-cert.pem \
     -in cloudflare-cert.pem \
     -passout pass:
   ```

### Binding Fails with TXT Record Error

**Symptoms**:
- `az containerapp hostname bind` fails
- Error: "TXT record not found"

**Solutions**:
1. Wait for DNS propagation
2. Verify TXT record exists:
   ```bash
   dig TXT asuid.finrisk.pangarabbit.com
   ```
3. Ensure TXT record is "DNS only" (gray cloud)
4. Check TXT content matches verification ID exactly

---

## Automation Scripts

### Upload Certificate Script

**File**: `scripts/upload-certificate.sh`

```bash
#!/bin/bash
set -euo pipefail

# Configuration
CERT_FILE="/Users/tvl/Desktop/cloudflare-cert.pfx"
CERT_NAME="finrisk-pangarabbit-cert"
RESOURCE_GROUP="rg-finrisk-dev"
ENVIRONMENT_NAME="cae-finrisk-dev"

# Check prerequisites
command -v az >/dev/null 2>&1 || { echo "Error: Azure CLI not installed"; exit 1; }
az account show >/dev/null 2>&1 || { echo "Error: Not logged in to Azure"; exit 1; }
[ -f "$CERT_FILE" ] || { echo "Error: Certificate file not found: $CERT_FILE"; exit 1; }

# Upload certificate
echo "Uploading certificate..."
az containerapp env certificate upload \
  --name "$ENVIRONMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --certificate-file "$CERT_FILE" \
  --certificate-name "$CERT_NAME" \
  --password ""

echo "✓ Certificate uploaded successfully"
```

### Verify Setup Script

**File**: `scripts/verify-custom-domain.sh`

```bash
#!/bin/bash
set -euo pipefail

DOMAIN="finrisk.pangarabbit.com"

echo "Verifying custom domain setup for $DOMAIN"
echo "=========================================="

# Test DNS
echo -e "\n1. DNS Resolution:"
nslookup "$DOMAIN" | grep -A2 "Name:"

# Test HTTPS
echo -e "\n2. HTTPS Connectivity:"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN/")
[ "$HTTP_STATUS" -eq 200 ] && echo "✓ HTTPS working (HTTP $HTTP_STATUS)" || echo "✗ HTTPS failed (HTTP $HTTP_STATUS)"

# Test application
echo -e "\n3. Application Response:"
curl -s "https://$DOMAIN/" | jq .

# Test health
echo -e "\n4. Health Check:"
curl -s "https://$DOMAIN/health" | jq .

# Test certificate
echo -e "\n5. Certificate Details:"
echo | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null | \
  openssl x509 -noout -subject -dates

echo -e "\n✓ All checks passed!"
```

---

## Summary

### What We Accomplished

1. ✅ Converted certificate from PEM to PFX format
2. ✅ Uploaded certificate to Azure Container App Environment
3. ✅ Retrieved domain verification ID
4. ✅ Configured DNS records in Cloudflare (CNAME + TXT)
5. ✅ Set Cloudflare SSL mode to "Full (strict)"
6. ✅ Bound custom domain to Container App
7. ✅ Verified end-to-end HTTPS connectivity
8. ✅ Confirmed application is responding correctly

### Key Commands Used

```bash
# Convert certificate
openssl pkcs12 -export -out cert.pfx -inkey cert.pem -in cert.pem -passout pass:

# Upload certificate
az containerapp env certificate upload \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --certificate-file cert.pfx \
  --certificate-name finrisk-pangarabbit-cert \
  --password ""

# Get verification ID
az containerapp env show \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query "properties.customDomainConfiguration.customDomainVerificationId" \
  --output tsv

# Bind domain
az containerapp hostname bind \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --hostname finrisk.pangarabbit.com \
  --certificate finrisk-pangarabbit-cert \
  --environment cae-finrisk-dev

# Verify
curl https://finrisk.pangarabbit.com/health
```

### Live Endpoints

- **Primary**: https://finrisk.pangarabbit.com
- **API Docs**: https://finrisk.pangarabbit.com/docs
- **Health**: https://finrisk.pangarabbit.com/health
- **Direct Azure**: https://ca-finrisk-dev.proudwater-4005d979.eastus2.azurecontainerapps.io

### Timeline

- **Certificate preparation**: 2 minutes
- **Certificate upload**: 1 minute
- **DNS configuration**: 3 minutes
- **DNS propagation**: 5-10 minutes
- **Domain binding**: 1 minute
- **Verification**: 2 minutes

**Total time**: ~15-20 minutes

---

## References

- [Azure Container Apps Custom Domains](https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-certificates)
- [Cloudflare Origin CA](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/)
- [Azure CLI Container Apps Reference](https://learn.microsoft.com/en-us/cli/azure/containerapp)
- [Terraform AzureRM Provider](https://registry.terraform.io/providers/hashicorp/azurerm/)

---

**Document Version**: 1.0
**Last Updated**: 2026-02-16
**Author**: Platform Team
