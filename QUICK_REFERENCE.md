# Custom Domain Quick Reference Card

## Live Configuration

| Item | Value |
|------|-------|
| **Custom Domain** | finrisk.pangarabbit.com |
| **Azure Resource** | ca-finrisk-dev |
| **Environment** | cae-finrisk-dev |
| **Resource Group** | rg-finrisk-dev |
| **Certificate Name** | finrisk-pangarabbit-cert |
| **Certificate Valid Until** | 2041-02-11 |
| **Azure FQDN** | ca-finrisk-dev.proudwater-4005d979.eastus2.azurecontainerapps.io |
| **Verification ID** | 7F9877DA54FDC73210D5C7D7F1776D6A757E6271FCEA153F3DDD87E9A3891299 |

## DNS Records (Cloudflare)

### CNAME Record
```
Type:    CNAME
Name:    finrisk
Target:  ca-finrisk-dev.proudwater-4005d979.eastus2.azurecontainerapps.io
Proxy:   ✅ Proxied (Orange cloud)
```

### TXT Record
```
Type:    TXT
Name:    asuid.finrisk
Content: 7F9877DA54FDC73210D5C7D7F1776D6A757E6271FCEA153F3DDD87E9A3891299
Proxy:   ⬜ DNS only (Gray cloud)
```

## SSL/TLS Configuration

**Cloudflare SSL Mode**: Full (strict)

---

## Key Commands

### Certificate Management

```bash
# Convert PEM to PFX
openssl pkcs12 -export \
  -out certificate.pfx \
  -inkey certificate.pem \
  -in certificate.pem \
  -passout pass:

# Upload certificate to Azure
az containerapp env certificate upload \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --certificate-file /path/to/certificate.pfx \
  --certificate-name finrisk-pangarabbit-cert \
  --password ""

# List certificates
az containerapp env certificate list \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev

# Delete certificate
az containerapp env certificate delete \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --certificate finrisk-pangarabbit-cert \
  --yes
```

### Custom Domain Binding

```bash
# Get verification ID
az containerapp env show \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query "properties.customDomainConfiguration.customDomainVerificationId" \
  --output tsv

# Bind custom domain
az containerapp hostname bind \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --hostname finrisk.pangarabbit.com \
  --certificate finrisk-pangarabbit-cert \
  --environment cae-finrisk-dev

# List custom domains
az containerapp hostname list \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev
```

### Verification & Testing

```bash
# Test DNS resolution
nslookup finrisk.pangarabbit.com

# Test TXT record
nslookup -type=TXT asuid.finrisk.pangarabbit.com

# Test HTTPS
curl -I https://finrisk.pangarabbit.com/

# Test application
curl https://finrisk.pangarabbit.com/
curl https://finrisk.pangarabbit.com/health

# Check certificate
echo | openssl s_client -connect finrisk.pangarabbit.com:443 \
  -servername finrisk.pangarabbit.com 2>/dev/null | \
  openssl x509 -noout -subject -dates

# View API docs
open https://finrisk.pangarabbit.com/docs
```

### Terraform (Optional)

```bash
# If using Terraform to manage custom domain reference
cd terraform/environments/dev
terraform plan -out=tfplan
terraform apply tfplan

# Get outputs
terraform output application_url
terraform output custom_domain_verification_id
```

---

## Troubleshooting Quick Checks

### DNS Not Resolving
```bash
# Check DNS globally
dig finrisk.pangarabbit.com
dig TXT asuid.finrisk.pangarabbit.com

# Check via Cloudflare DNS
dig @1.1.1.1 finrisk.pangarabbit.com
```

### SSL Certificate Issues
```bash
# Verify certificate in Azure
az containerapp env certificate list \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query "[].{Name:name, Valid:properties.valid, Expires:properties.expirationDate}"

# Check custom domain binding
az containerapp show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query "properties.configuration.ingress.customDomains"
```

### Application Not Responding
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

---

## Architecture Diagram

```
┌─────────────┐
│   Client    │
│  (Browser)  │
└──────┬──────┘
       │ HTTPS
       │ (Cloudflare Universal SSL)
       ▼
┌─────────────────┐
│   Cloudflare    │
│  Proxy (CDN +   │
│   DDoS + WAF)   │
└────────┬────────┘
         │ HTTPS
         │ (Cloudflare Origin Certificate)
         │ finrisk-pangarabbit-cert
         ▼
┌──────────────────────┐
│  Azure Container App │
│    (ca-finrisk-dev)  │
│                      │
│  ┌────────────────┐  │
│  │    FastAPI     │  │
│  │  Application   │  │
│  │   Port 8080    │  │
│  └────────────────┘  │
└──────────────────────┘
```

---

## URLs

| Endpoint | URL |
|----------|-----|
| **Custom Domain** | https://finrisk.pangarabbit.com |
| **API Documentation** | https://finrisk.pangarabbit.com/docs |
| **Health Check** | https://finrisk.pangarabbit.com/health |
| **Direct Azure** | https://ca-finrisk-dev.proudwater-4005d979.eastus2.azurecontainerapps.io |

---

## Security Checklist

- [x] Certificate uploaded to Azure (not in Terraform state)
- [x] Certificate files in `.gitignore`
- [x] Cloudflare SSL mode set to "Full (strict)"
- [x] DNS TXT record configured for verification
- [x] CNAME proxied through Cloudflare (DDoS protection)
- [x] HTTPS enforced (no HTTP access)
- [x] Certificate valid until 2041-02-11

---

## Maintenance Tasks

### Rotate Certificate (Before 2041)

1. Generate new Cloudflare Origin Certificate
2. Convert to PFX:
   ```bash
   openssl pkcs12 -export -out new-cert.pfx -inkey new-cert.pem -in new-cert.pem -passout pass:
   ```
3. Delete old certificate:
   ```bash
   az containerapp env certificate delete \
     --name cae-finrisk-dev \
     --resource-group rg-finrisk-dev \
     --certificate finrisk-pangarabbit-cert \
     --yes
   ```
4. Upload new certificate:
   ```bash
   az containerapp env certificate upload \
     --name cae-finrisk-dev \
     --resource-group rg-finrisk-dev \
     --certificate-file new-cert.pfx \
     --certificate-name finrisk-pangarabbit-cert \
     --password ""
   ```
5. Re-bind domain (if needed):
   ```bash
   az containerapp hostname bind \
     --name ca-finrisk-dev \
     --resource-group rg-finrisk-dev \
     --hostname finrisk.pangarabbit.com \
     --certificate finrisk-pangarabbit-cert \
     --environment cae-finrisk-dev
   ```

### Add Another Custom Domain

1. Ensure certificate covers the domain (wildcard or add SAN)
2. Add CNAME record in Cloudflare
3. Add TXT verification record
4. Wait for DNS propagation
5. Bind domain:
   ```bash
   az containerapp hostname bind \
     --name ca-finrisk-dev \
     --resource-group rg-finrisk-dev \
     --hostname new-subdomain.pangarabbit.com \
     --certificate finrisk-pangarabbit-cert \
     --environment cae-finrisk-dev
   ```

---

## Related Documentation

- **Detailed Guide**: `documentation/guides/custom-domain-step-by-step.md`
- **Certificate Setup**: `CERTIFICATE_SETUP.md`
- **DNS Configuration**: `DNS_CONFIGURATION.md`
- **Upload Script**: `scripts/upload-certificate.sh`
- **Verify Script**: `scripts/verify-custom-domain.sh`

---

**Last Updated**: 2026-02-16
