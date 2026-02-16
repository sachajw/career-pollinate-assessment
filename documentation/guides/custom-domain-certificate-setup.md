# Custom Domain and SSL Certificate Setup for Azure Container Apps

This guide explains how to configure a custom domain with SSL certificate for your Azure Container App.

## Overview

Your Azure Container App can use:
1. **Default domain**: `*.azurecontainerapps.io` (automatic HTTPS with Azure's certificate)
2. **Custom domain**: Your own domain (e.g., `api.pangarabbit.com`) with your own certificate

## Prerequisites

- Custom domain registered and DNS accessible
- SSL certificate in PFX format (PKCS12)
- Terraform 1.5+
- Azure CLI authenticated

## Certificate Formats

Azure Container Apps require certificates in **PFX (PKCS12) format**. If you have a PEM certificate:

```bash
# Convert PEM to PFX (no password)
openssl pkcs12 -export -out certificate.pfx \
  -inkey certificate.pem \
  -in certificate.pem \
  -passout pass:

# With password
openssl pkcs12 -export -out certificate.pfx \
  -inkey certificate.pem \
  -in certificate.pem \
  -passout pass:YourPassword123
```

## Setup Steps

### Step 1: Prepare Certificate

Convert your certificate to base64:

```bash
# Base64 encode the PFX certificate
base64 -i cloudflare-cert.pfx -o cloudflare-cert.pfx.b64

# Or in one line (macOS/Linux)
cat cloudflare-cert.pfx | base64 > cloudflare-cert.pfx.b64
```

### Step 2: Store Certificate in Terraform Variables

Add to `terraform/environments/dev/terraform.tfvars`:

```hcl
# Custom domain configuration
custom_domain_enabled   = true
custom_domain_name      = "api.pangarabbit.com"  # Your custom domain
certificate_name        = "pangarabbit-cert"     # Name for the cert in Azure
certificate_password    = ""                      # Empty if no password

# IMPORTANT: Do NOT commit this to git!
# Use environment variable or Azure Key Vault instead
certificate_blob_base64 = "MIIKUAIBAzCCCh..."  # Your base64-encoded cert
```

**Security Best Practice**: Use environment variables instead:

```bash
# Set via environment variable
export TF_VAR_certificate_blob_base64=$(cat cloudflare-cert.pfx.b64)
export TF_VAR_certificate_password=""

# Then run terraform without committing the cert
terraform plan
```

### Step 3: Update Dev Environment Configuration

Edit `terraform/environments/dev/main.tf`:

```hcl
module "container_app" {
  source = "../../modules/container-app"

  # ... existing configuration ...

  # Custom domain and certificate
  custom_domain_enabled   = var.custom_domain_enabled
  custom_domain_name      = var.custom_domain_name
  certificate_name        = var.certificate_name
  certificate_password    = var.certificate_password
  certificate_blob_base64 = var.certificate_blob_base64

  # ... rest of configuration ...
}
```

### Step 4: Add Variables to Environment

Edit `terraform/environments/dev/variables.tf`:

```hcl
# Custom domain configuration
variable "custom_domain_enabled" {
  description = "Enable custom domain with certificate"
  type        = bool
  default     = false
}

variable "custom_domain_name" {
  description = "Custom domain name"
  type        = string
  default     = ""
}

variable "certificate_name" {
  description = "Name for the certificate"
  type        = string
  default     = ""
}

variable "certificate_password" {
  description = "Certificate password"
  type        = string
  default     = ""
  sensitive   = true
}

variable "certificate_blob_base64" {
  description = "Base64-encoded certificate (PFX)"
  type        = string
  default     = ""
  sensitive   = true
}
```

### Step 5: Deploy Infrastructure

```bash
cd terraform/environments/dev

# Initialize Terraform (if not already done)
terraform init -backend-config=backend.hcl

# Set certificate via environment variable (secure)
export TF_VAR_certificate_blob_base64=$(cat ~/Desktop/cloudflare-cert.pfx.b64)
export TF_VAR_certificate_password=""
export TF_VAR_custom_domain_enabled=true
export TF_VAR_custom_domain_name="api.pangarabbit.com"
export TF_VAR_certificate_name="pangarabbit-cert"

# Plan and apply
terraform plan -out=tfplan
terraform apply tfplan
```

### Step 6: Configure DNS

After deployment, get the Container App's FQDN:

```bash
# Get the Container App URL
terraform output application_url

# Get the domain verification ID
terraform output -raw custom_domain_verification_id
```

Configure DNS records:

**For root domain (pangarabbit.com):**
```
Type: A
Name: @
Value: <container_app_static_ip>

Type: TXT
Name: asuid
Value: <custom_domain_verification_id>
```

**For subdomain (api.pangarabbit.com):**
```
Type: CNAME
Name: api
Value: <container_app_fqdn>

Type: TXT
Name: asuid.api
Value: <custom_domain_verification_id>
```

### Step 7: Cloudflare Configuration (If Using Cloudflare)

If using Cloudflare Origin Certificate:

1. **Add DNS records in Cloudflare**:
   - CNAME: `api` → `ca-finrisk-dev.azurecontainerapps.io`
   - TXT: `asuid.api` → `<verification_id>`

2. **Configure SSL/TLS Mode**:
   - Go to SSL/TLS → Overview
   - Set to **Full (strict)** for end-to-end encryption

3. **Proxy Status**:
   - Orange cloud (proxied) = Traffic goes through Cloudflare
   - Gray cloud (DNS only) = Direct to Azure

## Verification

Test your custom domain:

```bash
# Test HTTPS connectivity
curl -I https://api.pangarabbit.com/health

# Check certificate details
openssl s_client -connect api.pangarabbit.com:443 -servername api.pangarabbit.com < /dev/null | openssl x509 -noout -text

# Test via Cloudflare (if proxied)
curl -H "Host: api.pangarabbit.com" https://<azure-fqdn>/health
```

## Troubleshooting

### Certificate Upload Fails

**Error**: "The certificate password is incorrect"
```bash
# Verify PFX is valid
openssl pkcs12 -in cloudflare-cert.pfx -noout
# Enter password when prompted (or press Enter if no password)
```

**Error**: "Certificate format is invalid"
```bash
# Ensure it's a valid PKCS12 file
file cloudflare-cert.pfx
# Should output: "data" or "PKCS #12"

# Re-convert from PEM
openssl pkcs12 -export -out cloudflare-cert.pfx \
  -inkey cloudflare-cert.pem \
  -in cloudflare-cert.pem \
  -passout pass:
```

### Custom Domain Not Working

1. **Verify DNS propagation**:
   ```bash
   nslookup api.pangarabbit.com
   dig api.pangarabbit.com
   ```

2. **Check domain verification**:
   ```bash
   az containerapp env show \
     --name cae-finrisk-dev \
     --resource-group rg-finrisk-dev \
     --query customDomainConfiguration
   ```

3. **Check certificate binding**:
   ```bash
   az containerapp show \
     --name ca-finrisk-dev \
     --resource-group rg-finrisk-dev \
     --query "properties.configuration.ingress.customDomains"
   ```

### Cloudflare 526 Error (SSL handshake failed)

- Ensure SSL/TLS mode is set to **Full** (not Full Strict) initially
- Verify the certificate is correctly installed in Azure
- Check that the certificate matches the domain

## Security Best Practices

1. **Never commit certificates to Git**:
   ```bash
   # Add to .gitignore
   echo "*.pfx" >> .gitignore
   echo "*.pfx.b64" >> .gitignore
   echo "*.pem" >> .gitignore
   ```

2. **Use environment variables**:
   ```bash
   export TF_VAR_certificate_blob_base64=$(cat cert.pfx.b64)
   ```

3. **Store in Azure Key Vault** (production):
   ```bash
   # Store certificate in Key Vault
   az keyvault certificate import \
     --vault-name kv-finrisk-dev \
     --name pangarabbit-cert \
     --file cloudflare-cert.pfx

   # Reference in Terraform via data source
   data "azurerm_key_vault_certificate" "custom_cert" {
     name         = "pangarabbit-cert"
     key_vault_id = module.key_vault.id
   }
   ```

4. **Rotate certificates before expiry**:
   - Cloudflare Origin Certificates are valid for 15 years
   - Set a reminder to rotate before expiry
   - Update Terraform variable and re-apply

## Alternative: Azure Key Vault Integration

For production, store certificates in Key Vault:

```hcl
# Reference certificate from Key Vault
data "azurerm_key_vault_certificate" "app_cert" {
  name         = "app-certificate"
  key_vault_id = var.key_vault_id
}

# Use in Container App
module "container_app" {
  # ...
  certificate_blob_base64 = data.azurerm_key_vault_certificate.app_cert.certificate_data_base64
  # ...
}
```

## Cost Implications

- **Custom domains**: Free on Azure Container Apps
- **Certificates**: Free with Cloudflare Origin Certificate or Let's Encrypt
- **Azure-managed certificates**: Free for `*.azurecontainerapps.io` domains

## References

- [Azure Container Apps Custom Domains](https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-certificates)
- [Cloudflare Origin CA](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/)
- [Terraform azurerm_container_app_environment_certificate](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app_environment_certificate)
