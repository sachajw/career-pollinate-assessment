# ADR-001: Use Azure Container Apps for Compute Platform

**Status:** Accepted
**Date:** 2026-02-14
**Decision Makers:** Platform Engineering Team
**Technical Story:** RiskShield API Integration Platform

## Context

FinSure Capital requires a compute platform to host the RiskShield API integration service. The platform must be:

- Cost-effective for variable workloads
- Scalable to handle peak loan application periods
- Secure with managed identity support
- Observable with native Azure monitoring
- Easy to deploy and maintain

We need to choose between:

1. Azure Container Apps
2. Azure App Service (Container)
3. Azure Kubernetes Service (AKS)
4. Azure Functions (Containerized)

## Decision

We will use **Azure Container Apps** as the compute platform for the RiskShield integration service.

## Decision Drivers

| Criterion              | Weight | Container Apps | App Service | AKS        | Functions |
| ---------------------- | ------ | -------------- | ----------- | ---------- | --------- |
| **Cost Efficiency**    | High   | ⭐⭐⭐⭐⭐     | ⭐⭐⭐      | ⭐⭐       | ⭐⭐⭐⭐  |
| **Ease of Management** | High   | ⭐⭐⭐⭐⭐     | ⭐⭐⭐⭐⭐  | ⭐⭐       | ⭐⭐⭐⭐  |
| **Scalability**        | High   | ⭐⭐⭐⭐⭐     | ⭐⭐⭐⭐    | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐  |
| **Cold Start Time**    | Medium | ⭐⭐⭐⭐       | ⭐⭐⭐⭐⭐  | ⭐⭐⭐⭐⭐ | ⭐⭐⭐    |
| **Container Support**  | High   | ⭐⭐⭐⭐⭐     | ⭐⭐⭐⭐    | ⭐⭐⭐⭐⭐ | ⭐⭐⭐    |
| **Network Isolation**  | High   | ⭐⭐⭐⭐       | ⭐⭐⭐⭐    | ⭐⭐⭐⭐⭐ | ⭐⭐⭐    |
| **Team Familiarity**   | Medium | ⭐⭐⭐         | ⭐⭐⭐⭐⭐  | ⭐⭐       | ⭐⭐⭐⭐  |
| **Future Flexibility** | Medium | ⭐⭐⭐⭐⭐     | ⭐⭐⭐      | ⭐⭐⭐⭐⭐ | ⭐⭐⭐    |

### Detailed Analysis

#### Azure Container Apps (Selected)

**Pros:**

- **Scale to Zero**: Pay only when processing requests (~70% cost savings in dev)
- **KEDA Integration**: Event-driven autoscaling based on HTTP requests, queues, etc.
- **Dapr Built-in**: Future-ready for service mesh, pub/sub patterns
- **Managed K8s**: Kubernetes benefits without operational overhead
- **Consumption Pricing**: Pay per vCPU-second and memory GB-second
- **Fast Deployment**: Simple container deployment without cluster management
- **VNet Integration**: Private networking support

**Cons:**

- **Newer Service**: Less mature than App Service (GA: May 2022)
- **Cold Start**: 2-3s cold start latency (mitigated by min replicas)
- **Limited Customization**: Less control than full AKS
- **Regional Availability**: Not available in all Azure regions (check: East US 2 ✅)

**Cost Estimate** (East US 2, Azure Retail Prices API, Feb 2026):

- Dev (min_replicas=0, scale-to-zero): **~$0/month** — free grant covers typical dev traffic (180,000 vCPU-s and 360,000 GiB-s free per month; $0.000024/vCPU-s, $0.000003/GiB-s beyond)
- Prod (min_replicas=2, 24/7): **~$72/month** — 2,412,000 billable vCPU-s × $0.000024 + 4,824,000 billable GiB-s × $0.000003

#### Azure App Service (Considered)

**Pros:**

- **Mature Platform**: Long history, extensive documentation
- **No Cold Start**: Always-on instances
- **Deployment Slots**: Blue/green deployments built-in
- **Team Familiarity**: Well-known service

**Cons:**

- **Cost**: Minimum ~$100/month (P1v3 tier for production)
- **Scaling**: Basic autoscaling compared to KEDA
- **No Dapr**: Limited service mesh capabilities
- **Always-On**: Cannot scale to zero

**Cost Estimate** (East US 2, Feb 2026):

- Dev B1 Linux (1 vCPU, 1.75 GB): ~$12/month always-on ($0.017/hr × 730h); no scale-to-zero
- Prod P1v3 Linux (2 vCPU, 8 GB): ~$113/month always-on ($0.155/hr × 730h)

#### AKS (Rejected)

**Pros:**

- **Full Control**: Complete Kubernetes flexibility
- **Advanced Networking**: Full CNI, network policies
- **Enterprise Features**: AAD Pod Identity, Azure Policy

**Cons:**

- **Operational Overhead**: Cluster management, patching, upgrades
- **Cost**: Minimum ~$150/month for control plane + nodes
- **Complexity**: Overkill for single-service deployment
- **Team Skills**: Requires Kubernetes expertise

**Cost Estimate:**

- Prod: ~$500/month (3-node cluster, Standard D2s v3)

#### Azure Functions (Rejected)

**Pros:**

- **Serverless**: True consumption model
- **Event-Driven**: Native trigger support

**Cons:**

- **Execution Time Limit**: 10 minutes max (Premium plan)
- **Cold Start**: Can be 5-10s for .NET/Java
- **Container Support**: Limited compared to Container Apps
- **Not REST API Native**: Better for event-driven, not long-running HTTP

## Consequences

### Positive

- **Reduced Costs**: Scale-to-zero capability saves 50-70% in non-production environments
- **Simplified Operations**: No cluster management overhead
- **Future-Ready**: Dapr integration enables easy migration to microservices if needed
- **Fast Time-to-Market**: Quick setup and deployment
- **Cloud-Native**: Aligns with modern application patterns

### Negative

- **Cold Start Latency**: 2-3s cold start (mitigated by min replicas in prod)
- **Platform Lock-in**: Container Apps is Azure-specific (vs. AKS portability)
- **Learning Curve**: Team needs to learn Container Apps vs. familiar App Service
- **Limited Customization**: Less control over underlying infrastructure

### Neutral

- **Monitoring**: Application Insights works equally well across all options
- **Managed Identity**: All options support managed identity
- **VNet Integration**: All options support private networking

## Mitigations

### Cold Start Mitigation

- **Production**: Set `minReplicas: 2` to ensure always-on instances
- **Development**: Accept cold start as cost trade-off
- **Health Probes**: Configure aggressive health checks to prevent scale-to-zero during business hours

### Team Skills Gap

- **Training**: Allocate 2 weeks for team upskilling on Container Apps
- **Documentation**: Create runbooks for common operations
- **Comparison Guide**: Document differences vs. App Service for team reference

### Platform Lock-in

- **Abstraction**: Keep business logic container-portable
- **Exit Strategy**: Container Apps uses standard Kubernetes concepts (can migrate to AKS if needed)
- **Multi-Cloud Consideration**: Not a current requirement, re-evaluate if needed

## Compliance & Security

- **ISO 27001**: Container Apps is ISO 27001 certified ✅
- **SOC 2 Type II**: Compliance maintained ✅
- **HIPAA/PCI DSS**: Not applicable for this use case ✅
- **Managed Identity**: Fully supported ✅
- **Private Endpoints**: Supported for production ✅

## Alternatives Considered

### 1. Hybrid Approach

- **Dev/Staging**: Container Apps (cost savings)
- **Production**: App Service (no cold start)

**Rejected because:**

- Increases complexity with two deployment targets
- Reduces environment parity
- Cold start mitigated by min replicas

### 2. Service Fabric

- Rejected due to legacy platform status and migration to Container Apps

### 3. VM-based Deployment

- Rejected due to high operational overhead and cost

## Related Decisions

- [ADR-002: Python Runtime Selection](./002-python-runtime.md)
- [ADR-003: Managed Identity for Azure Authentication](./003-managed-identity-security.md)

## References

- [Azure Container Apps Documentation](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Container Apps vs. App Service Decision Guide](https://learn.microsoft.com/en-us/azure/container-apps/compare-options)
- [KEDA Scalers](https://keda.sh/docs/scalers/)
- [Azure Container Apps Pricing](https://azure.microsoft.com/en-us/pricing/details/container-apps/)

## Review & Approval

| Role                      | Name   | Date       | Status      |
| ------------------------- | ------ | ---------- | ----------- |
| Solution Architect        | [Name] | 2026-02-14 | ✅ Approved |
| Platform Engineering Lead | [Name] | 2026-02-14 | ✅ Approved |
| Security Architect        | [Name] | 2026-02-14 | ✅ Approved |
| FinOps Lead               | [Name] | 2026-02-14 | ✅ Approved |

---

**Last Updated:** 2026-02-14
**Next Review:** 2026-08-14 (6 months)
