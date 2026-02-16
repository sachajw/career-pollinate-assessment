# DNS Configuration for finrisk.pangarabbit.com

**Status**: ✅ Certificate uploaded | ⏳ Awaiting DNS configuration

## Quick Reference

| Item | Value |
|------|-------|
| **Custom Domain** | finrisk.pangarabbit.com |
| **Azure FQDN** | ca-finrisk-dev.proudwater-4005d979.eastus2.azurecontainerapps.io |
| **Verification ID** | 7F9877DA54FDC73210D5C7D7F1776D6A757E6271FCEA153F3DDD87E9A3891299 |
| **Certificate** | finrisk-pangarabbit-cert (valid until 2041-02-11) |

---

## Step 1: Add DNS Records in Cloudflare

Go to: https://dash.cloudflare.com → **pangarabbit.com** → DNS → Records

### Record #1: CNAME (Traffic Routing)

```
Type:    CNAME
Name:    finrisk
Target:  ca-finrisk-dev.proudwater-4005d979.eastus2.azurecontainerapps.io
Proxy:   ✅ Proxied (Orange cloud)
TTL:     Auto
```

### Record #2: TXT (Domain Verification)

```
Type:    TXT
Name:    asuid.finrisk
Content: 7F9877DA54FDC73210D5C7D7F1776D6A757E6271FCEA153F3DDD87E9A3891299
Proxy:   ⬜ DNS only (Gray cloud)
TTL:     Auto
```

---

## Step 2: Configure SSL/TLS

Go to: SSL/TLS → Overview

**Set encryption mode to**: `Full (strict)`

---

## Step 3: Wait for DNS Propagation

Check DNS:
```bash
nslookup finrisk.pangarabbit.com
nslookup asuid.finrisk.pangarabbit.com
```

Expected:
- `finrisk.pangarabbit.com` → Cloudflare IP addresses
- `asuid.finrisk.pangarabbit.com` → TXT record with verification ID

Propagation usually takes **5-10 minutes**.

---

## Step 4: Bind Custom Domain (After DNS propagates)

Run this command:

```bash
az containerapp hostname bind \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --hostname finrisk.pangarabbit.com \
  --certificate finrisk-pangarabbit-cert \
  --environment cae-finrisk-dev
```

---

## Step 5: Verify

Test HTTPS connectivity:
```bash
curl -I https://finrisk.pangarabbit.com/health
```

Check certificate:
```bash
echo | openssl s_client -connect finrisk.pangarabbit.com:443 \
  -servername finrisk.pangarabbit.com 2>/dev/null | \
  openssl x509 -noout -subject -dates
```

---

## Troubleshooting

### DNS not resolving
```bash
# Check propagation globally
dig finrisk.pangarabbit.com
dig asuid.finrisk.pangarabbit.com TXT

# Query Cloudflare DNS directly
dig finrisk.pangarabbit.com @1.1.1.1
```

### Binding fails with "TXT record not found"
- Wait a few more minutes for DNS propagation
- Verify TXT record is correct in Cloudflare
- Ensure TXT record is **DNS only** (gray cloud), not proxied

### 526 SSL error after binding
1. Verify Cloudflare SSL mode is "Full (strict)"
2. Check certificate is correctly bound to container app
3. Test direct Azure endpoint first (bypass Cloudflare)

---

## Architecture

```
┌──────────┐    HTTPS     ┌────────────┐    HTTPS     ┌──────────────────┐
│  Client  │ ──────────> │ Cloudflare │ ──────────> │  Azure Container │
│          │              │   Proxy    │              │       App        │
└──────────┘              └────────────┘              └──────────────────┘
                               │                              │
                         Universal SSL           Cloudflare Origin Cert
                         (Cloudflare)            (finrisk-pangarabbit-cert)
```

---

## Current Status

- ✅ Infrastructure deployed (Container App Environment)
- ✅ Certificate uploaded to Azure (finrisk-pangarabbit-cert)
- ✅ Certificate valid until 2041-02-11
- ⏳ DNS configuration in Cloudflare (manual step required)
- ⏳ Custom domain binding (after DNS propagates)
- ⏳ SSL/TLS verification

---

## Next Actions

1. **You**: Configure DNS records in Cloudflare dashboard
2. **You**: Set SSL/TLS to "Full (strict)"
3. **Wait**: 5-10 minutes for DNS propagation
4. **Run**: `az containerapp hostname bind` command (or ask me to run it)
5. **Test**: `curl -I https://finrisk.pangarabbit.com/health`

---

## Reference Commands

```bash
# Check certificate status
az containerapp env certificate list \
  --name cae-finrisk-dev \
  --resource-group rg-finrisk-dev

# View container app ingress
az containerapp show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query "properties.configuration.ingress"

# List custom domains
az containerapp hostname list \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev
```

---

**Last Updated**: $(date)
