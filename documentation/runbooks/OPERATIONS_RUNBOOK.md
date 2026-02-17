# Operations Runbook

This runbook provides operational procedures for the Risk Scoring API.

## Service Overview

| Property           | Value                 |
| ------------------ | --------------------- |
| Service Name       | Risk Scoring API      |
| Technology         | FastAPI (Python 3.13) |
| Platform           | Azure Container Apps  |
| Port               | 8080                  |
| Health Endpoint    | `/health`             |
| Readiness Endpoint | `/ready`              |

## Quick Reference

### Key Endpoints

```bash
# Health check
curl https://<app-url>/health

# Readiness check
curl https://<app-url>/ready

# Validate request
curl -X POST https://<app-url>/api/v1/validate \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"firstName":"Test","lastName":"User","idNumber":"9001011234088"}'
```

### Useful Commands

```bash
# View application logs
az containerapp logs show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --follow

# View recent logs
az containerapp logs show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --tail 100

# Get application URL
az containerapp show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query properties.configuration.ingress.fqdn \
  --output tsv

# Restart application
az containerapp revision restart \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev
```

---

## Incident Response

### Severity Levels

| Level         | Description                          | Response Time |
| ------------- | ------------------------------------ | ------------- |
| P1 - Critical | Service down, data loss              | 15 minutes    |
| P2 - High     | Degraded performance, partial outage | 1 hour        |
| P3 - Medium   | Feature not working                  | 4 hours       |
| P4 - Low      | Minor issue, workaround available    | 24 hours      |

### Incident Response Steps

1. **Acknowledge** - Confirm incident and assign owner
2. **Assess** - Determine severity and impact
3. **Communicate** - Notify stakeholders
4. **Mitigate** - Apply workaround or fix
5. **Resolve** - Implement permanent fix
6. **Postmortem** - Document learnings

---

## Common Issues

### Issue: Application Not Responding

**Symptoms:**

- Health checks failing
- 503 Service Unavailable
- Connection timeouts

**Diagnosis:**

```bash
# Check container app status
az containerapp show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query "{status:properties.runningStatus, replicas:properties.template.scale.minReplicas}"

# Check recent logs
az containerapp logs show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --tail 50

# Check revision status
az containerapp revision list \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query "[].{name:name,status:properties.runningState,trafficWeight:properties.trafficWeight}"
```

**Resolution:**

1. Check if scale-to-zero (cold start issue):

   ```bash
   # Wait 10 seconds and retry health check
   sleep 10 && curl https://<app-url>/health
   ```

2. Check for crash loops:

   ```bash
   az containerapp revision restart \
     --name ca-finrisk-dev \
     --resource-group rg-finrisk-dev
   ```

3. Rollback to previous revision if needed (see Rollback section)

---

### Issue: RiskShield API Errors

**Symptoms:**

- 502/503 errors on validation
- Timeout errors
- Intermittent failures

**Diagnosis:**

```bash
# Search logs for RiskShield errors
az containerapp logs show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --tail 500 | grep -i "riskshield"
```

**Resolution:**

1. **Circuit breaker open:**
   - Wait for recovery timeout (30 seconds default)
   - Circuit will auto-recover

2. **Rate limited by RiskShield:**
   - Check if quota exceeded
   - Contact RiskShield support if persistent

3. **Auth failure:**

   ```bash
   # Verify API key in Key Vault
   az keyvault secret show \
     --vault-name kv-finrisk-dev \
     --name RISKSHIELD-API-KEY \
     --query value -o tsv

   # Rotate key if compromised
   az keyvault secret set \
     --vault-name kv-finrisk-dev \
     --name RISKSHIELD-API-KEY \
     --value "new-api-key"
   ```

---

### Issue: High Error Rate

**Symptoms:**

- Elevated 4xx/5xx responses
- Application Insights alerts

**Diagnosis:**

```bash
# Check Application Insights for errors
az monitor app-insights query \
  --app <app-insights-name> \
  --resource-group rg-finrisk-dev \
  --analytics-query "
    requests
    | where timestamp > ago(1h)
    | where success == false
    | summarize count() by resultCode
    | order by count_ desc
  "
```

**Resolution:**

1. Identify error pattern from logs
2. Check for upstream service issues
3. Review recent deployments
4. Check resource utilization

---

### Issue: Memory/CPU Alerts

**Symptoms:**

- Container restart
- Slow response times
- OOMKilled events

**Diagnosis:**

```bash
# Check container metrics
az containerapp show \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query "properties.template.containers[0].{cpu:resources.cpu,memory:resources.memory}"

# View metrics in Azure Monitor
az monitor metrics list \
  --resource <container-app-resource-id> \
  --metric "CPUUsage","MemoryWorkingSetBytes"
```

**Resolution:**

1. Scale up resources:

   ```bash
   az containerapp update \
     --name ca-finrisk-dev \
     --resource-group rg-finrisk-dev \
     --cpu 1.0 \
     --memory 2.0Gi
   ```

2. Scale out replicas:
   ```bash
   az containerapp update \
     --name ca-finrisk-dev \
     --resource-group rg-finrisk-dev \
     --min-replicas 2 \
     --max-replicas 10
   ```

---

## Deployment Procedures

### Standard Deployment

Deployments are handled automatically via Azure DevOps pipeline on merge to main.

```bash
# Monitor deployment
az containerapp revision list \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query "[].{name:name,createdTime:properties.createdTime,status:properties.runningState}"
```

### Manual Deployment

```bash
# Update container image
az containerapp update \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --image acrfinriskdev.azurecr.io/applicant-validator:v1.2.3

# Verify deployment
curl https://<app-url>/health
```

### Rollback Procedure

```bash
# List revisions
az containerapp revision list \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --query "[].{name:name,createdTime:properties.createdTime,active:properties.active,status:properties.runningState}"

# Rollback to previous revision
az containerapp revision set-mode \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --mode Single

# Deactivate failing revision
az containerapp revision deactivate \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --revision <revision-name>

# Or reroute traffic to previous revision
az containerapp update \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev \
  --set-traffic <old-revision>=100
```

---

## Secret Management

### View Secrets in Key Vault

```bash
# List secrets
az keyvault secret list \
  --vault-name kv-finrisk-dev

# Get secret value (use with caution)
az keyvault secret show \
  --vault-name kv-finrisk-dev \
  --name RISKSHIELD-API-KEY \
  --query value -o tsv
```

### Rotate API Key

```bash
# 1. Generate new key with RiskShield
# 2. Update in Key Vault
az keyvault secret set \
  --vault-name kv-finrisk-dev \
  --name RISKSHIELD-API-KEY \
  --value "new-api-key-from-riskshield"

# 3. Restart app to pick up new key (or wait for natural recycle)
az containerapp revision restart \
  --name ca-finrisk-dev \
  --resource-group rg-finrisk-dev

# 4. Verify with test request
curl -X POST https://<app-url>/api/v1/validate \
  -H "Authorization: Bearer test-key" \
  -H "Content-Type: application/json" \
  -d '{"firstName":"Test","lastName":"User","idNumber":"9001011234088"}'
```

---

## Monitoring

### Key Metrics to Monitor

| Metric       | Threshold | Alert    |
| ------------ | --------- | -------- |
| Error Rate   | > 1%      | Warning  |
| Error Rate   | > 5%      | Critical |
| P95 Latency  | > 2s      | Warning  |
| P95 Latency  | > 5s      | Critical |
| Availability | < 99%     | Critical |
| CPU Usage    | > 80%     | Warning  |
| Memory Usage | > 85%     | Warning  |

### Log Queries

**Recent errors:**

```kusto
traces
| where timestamp > ago(1h)
| where severityLevel >= 3
| project timestamp, message, operation_Name
| order by timestamp desc
```

**Request latency by endpoint:**

```kusto
requests
| where timestamp > ago(1h)
| summarize avg(duration), percentiles(duration, 95, 99) by name
| order by avg_duration desc
```

**Requests by error code:**

```kusto
requests
| where timestamp > ago(1h)
| where success == false
| summarize count() by resultCode
| render piechart
```

---

## Escalation

### On-Call Contacts

| Role                | Contact             | Escalation Order |
| ------------------- | ------------------- | ---------------- |
| Primary On-Call     | #platform-oncall    | 1                |
| Secondary On-Call   | #platform-secondary | 2                |
| Platform Lead       | #platform-lead      | 3                |
| Engineering Manager | #eng-manager        | 4                |

### External Contacts

| Service            | Contact                | SLA      |
| ------------------ | ---------------------- | -------- |
| RiskShield Support | support@riskshield.com | 4 hours  |
| Azure Support      | Azure Portal           | Per plan |

---

## Checklists

### Deployment Checklist

- [ ] All tests passing in CI/CD
- [ ] Security scan completed (no critical issues)
- [ ] Change approved via PR review
- [ ] Rollback plan documented
- [ ] Monitoring dashboards visible
- [ ] Stakeholders notified

### Post-Incident Checklist

- [ ] Incident resolved
- [ ] Root cause identified
- [ ] Postmortem document created
- [ ] Action items assigned
- [ ] Monitoring improvements implemented
- [ ] Runbook updated if needed
