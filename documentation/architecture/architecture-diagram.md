# Architecture Diagrams

## High-Level System Architecture

```mermaid
graph TB
    subgraph "External Systems"
        LOS[Loan Origination System]
        RISK[RiskShield API<br/>api.riskshield.com]
    end

    subgraph "Azure Platform - Production"
        subgraph "Edge Layer"
            AFD[Azure Front Door<br/>WAF + DDoS]
        end

        subgraph "Application Layer"
            ACA[Azure Container Apps<br/>Risk Scoring API<br/>Min: 2, Max: 10]
        end

        subgraph "Security & Secrets"
            KV[Azure Key Vault<br/>API Keys + Secrets]
            MI[Managed Identity<br/>System Assigned]
        end

        subgraph "Container Registry"
            ACR[Azure Container Registry<br/>Premium + Geo-Replication]
        end

        subgraph "Observability"
            AI[Application Insights<br/>APM + Tracing]
            LA[Log Analytics<br/>Centralized Logging]
        end

        subgraph "Networking"
            PE[Private Endpoints]
            VNET[Virtual Network]
        end
    end

    subgraph "DevOps Platform"
        ADO[Azure DevOps<br/>CI/CD Pipelines]
        TF[Terraform<br/>IaC State]
    end

    LOS -->|HTTPS POST /validate| AFD
    AFD -->|Internal Routing| ACA
    ACA -->|Get Secret| KV
    ACA -->|POST /v1/score| RISK
    ACA -->|Telemetry| AI
    ACA -->|Logs| LA
    MI -.->|RBAC Auth| KV
    MI -.->|Pull Images| ACR
    ADO -->|Deploy Container| ACA
    ADO -->|Push Images| ACR
    ADO -->|Provision Infra| TF
    PE -.->|Secure Access| KV
    VNET -.->|Network Isolation| ACA

    style AFD fill:#0078d4,stroke:#fff,color:#fff
    style ACA fill:#0078d4,stroke:#fff,color:#fff
    style KV fill:#ffb900,stroke:#fff,color:#000
    style ACR fill:#0078d4,stroke:#fff,color:#fff
    style AI fill:#00bcf2,stroke:#fff,color:#000
    style RISK fill:#e74c3c,stroke:#fff,color:#fff
```

## Deployment Architecture

```mermaid
graph LR
    subgraph "Developer Workflow"
        DEV[Developer]
        GIT[Git Repository]
    end

    subgraph "CI/CD Pipeline"
        BUILD[Build Stage<br/>- Lint<br/>- Test<br/>- Docker Build]
        SCAN[Security Scan<br/>- Trivy<br/>- SAST]
        PUSH[Push to ACR]
        INFRA[Terraform Stage<br/>- Plan<br/>- Apply]
        DEPLOY[Deploy Stage<br/>- Container Update<br/>- Health Check]
    end

    subgraph "Environments"
        DEVENV[Dev Environment]
        STAGENV[Staging Environment]
        PRODENV[Production Environment<br/>Manual Approval]
    end

    DEV -->|git push| GIT
    GIT -->|Trigger| BUILD
    BUILD --> SCAN
    SCAN --> PUSH
    PUSH --> INFRA
    INFRA --> DEPLOY
    DEPLOY -->|Auto Deploy| DEVENV
    DEPLOY -->|Auto Deploy| STAGENV
    DEPLOY -->|Manual Gate| PRODENV

    style BUILD fill:#4caf50,stroke:#fff,color:#fff
    style SCAN fill:#ff9800,stroke:#fff,color:#fff
    style PRODENV fill:#f44336,stroke:#fff,color:#fff
```

## Data Flow Diagram

```mermaid
sequenceDiagram
    participant Client as Loan System
    participant API as Risk Scoring API
    participant KV as Key Vault
    participant RS as RiskShield API
    participant AI as App Insights

    Client->>API: POST /validate<br/>{firstName, lastName, idNumber}
    activate API

    Note over API: Generate Correlation ID
    API->>AI: Log: Request Received

    API->>API: Validate Input Schema

    API->>KV: Get Secret (RISKSHIELD_API_KEY)<br/>via Managed Identity
    activate KV
    KV-->>API: Return API Key
    deactivate KV

    API->>RS: POST /v1/score<br/>Header: X-API-Key<br/>Body: Applicant Data
    activate RS

    Note over RS: Process Risk Scoring

    RS-->>API: {riskScore: 72, riskLevel: "MEDIUM"}
    deactivate RS

    API->>AI: Log: External API Success<br/>Duration: 234ms

    API->>API: Transform Response

    API-->>Client: {riskScore: 72, riskLevel: "MEDIUM",<br/>correlationId: "uuid"}
    deactivate API

    API->>AI: Log: Request Completed
```

## Security Architecture

```mermaid
graph TB
    subgraph "Security Layers"
        subgraph "Layer 1: Edge Protection"
            WAF[Web Application Firewall<br/>OWASP Top 10]
            DDOS[DDoS Protection<br/>Azure DDoS Standard]
            TLS[TLS 1.2+ Only<br/>HTTPS Enforcement]
        end

        subgraph "Layer 2: Identity & Access"
            MI[Managed Identity<br/>Password-less Auth]
            RBAC[Azure RBAC<br/>Least Privilege]
            AAD[Azure AD Integration<br/>Optional]
        end

        subgraph "Layer 3: Network Security"
            PE[Private Endpoints<br/>Key Vault Access]
            NSG[Network Security Groups<br/>Traffic Filtering]
            VNET[VNet Integration<br/>Isolated Network]
        end

        subgraph "Layer 4: Application Security"
            INPUT[Input Validation<br/>Schema Checks]
            RATE[Rate Limiting<br/>100 req/min]
            TIMEOUT[Timeout Protection<br/>30s Max]
        end

        subgraph "Layer 5: Data Protection"
            KV[Key Vault Secrets<br/>No Env Variables]
            ENCRYPT[Encryption at Rest<br/>Azure-Managed Keys]
            ROTATE[Secret Rotation<br/>90-day Policy]
        end

        subgraph "Layer 6: Monitoring & Response"
            AUDIT[Audit Logging<br/>All Key Vault Access]
            ALERT[Security Alerts<br/>Anomaly Detection]
            THREAT[Threat Intelligence<br/>Azure Defender]
        end
    end

    WAF --> MI
    DDOS --> MI
    TLS --> MI
    MI --> PE
    RBAC --> PE
    PE --> INPUT
    NSG --> INPUT
    VNET --> INPUT
    INPUT --> KV
    RATE --> KV
    TIMEOUT --> KV
    KV --> AUDIT
    ENCRYPT --> AUDIT
    ROTATE --> AUDIT
    AUDIT --> ALERT
    ALERT --> THREAT

    style WAF fill:#f44336,stroke:#fff,color:#fff
    style DDOS fill:#f44336,stroke:#fff,color:#fff
    style MI fill:#4caf50,stroke:#fff,color:#fff
    style KV fill:#ffb900,stroke:#fff,color:#000
    style AUDIT fill:#00bcf2,stroke:#fff,color:#000
```

## Infrastructure Components

```mermaid
graph TB
    subgraph "Resource Group: rg-riskscoring-prod"
        subgraph "Compute"
            ACA[Container App<br/>risk-scoring-api<br/>0.5 vCPU, 1Gi RAM]
        end

        subgraph "Storage & Registry"
            ACR[Container Registry<br/>acrriskscoring<br/>Premium Tier]
            STORAGE[Storage Account<br/>Terraform State<br/>LRS]
        end

        subgraph "Security"
            KV[Key Vault<br/>kv-riskscoring<br/>Soft Delete + Purge Protection]
            MI[Managed Identity<br/>id-riskscoring-api]
        end

        subgraph "Monitoring"
            LA[Log Analytics Workspace<br/>90-day Retention]
            AI[Application Insights<br/>Distributed Tracing]
        end

        subgraph "Networking (Prod)"
            VNET[Virtual Network<br/>10.0.0.0/16]
            PE1[Private Endpoint<br/>Key Vault]
            NSG[Network Security Group]
        end
    end

    ACA -->|Uses| MI
    ACA -->|Pulls Images| ACR
    ACA -->|Reads Secrets| KV
    ACA -->|Sends Logs| LA
    ACA -->|Sends Telemetry| AI
    MI -->|Has Role| KV
    MI -->|Has Role| ACR
    PE1 -->|Secures| KV
    NSG -->|Protects| VNET
    VNET -->|Contains| ACA

    style ACA fill:#0078d4,stroke:#fff,color:#fff
    style KV fill:#ffb900,stroke:#fff,color:#000
    style LA fill:#00bcf2,stroke:#fff,color:#000
```

## Observability Architecture

```mermaid
graph TB
    subgraph "Application Layer"
        APP[Risk Scoring API]
    end

    subgraph "Telemetry Collection"
        APPINSIGHTS[Application Insights SDK<br/>Automatic Instrumentation]
    end

    subgraph "Data Ingestion"
        LA[Log Analytics<br/>Kusto Query Language]
    end

    subgraph "Visualization"
        DASH[Azure Dashboards<br/>Custom Metrics]
        WORKBOOK[Azure Workbooks<br/>Interactive Reports]
    end

    subgraph "Alerting"
        ALERTS[Alert Rules<br/>- Error Rate > 5%<br/>- Latency P95 > 2s<br/>- Availability < 99.9%]
        AG[Action Groups<br/>- PagerDuty<br/>- Email<br/>- Slack Webhook]
    end

    subgraph "External Monitoring"
        PING[Availability Tests<br/>5-min Intervals]
    end

    APP -->|Logs, Metrics, Traces| APPINSIGHTS
    APPINSIGHTS -->|Ingest| LA
    LA -->|Query| DASH
    LA -->|Query| WORKBOOK
    LA -->|Trigger| ALERTS
    ALERTS -->|Notify| AG
    PING -->|Test Endpoint| APP
    PING -->|Results| APPINSIGHTS

    style APPINSIGHTS fill:#00bcf2,stroke:#fff,color:#000
    style ALERTS fill:#f44336,stroke:#fff,color:#fff
```

## Network Architecture - Production

```mermaid
graph TB
    subgraph "Internet"
        INTERNET[Public Internet]
    end

    subgraph "Azure - East US 2"
        subgraph "Edge Services"
            AFD[Azure Front Door<br/>WAF Enabled]
        end

        subgraph "VNet: 10.0.0.0/16"
            subgraph "Container Apps Subnet: 10.0.1.0/24"
                ACA[Container Apps<br/>Internal Ingress]
            end

            subgraph "Private Endpoint Subnet: 10.0.2.0/24"
                PE_KV[PE: Key Vault]
                PE_ACR[PE: ACR]
            end

            subgraph "Integration Subnet: 10.0.3.0/24"
                NAT[NAT Gateway<br/>Outbound to Internet]
            end
        end

        subgraph "PaaS Services"
            KV[Key Vault<br/>Private Access Only]
            ACR[Container Registry<br/>Private Access]
        end
    end

    subgraph "External Services"
        RISK[RiskShield API<br/>Internet]
    end

    INTERNET -->|HTTPS| AFD
    AFD -->|Internal Routing| ACA
    ACA -->|Private Link| PE_KV
    ACA -->|Private Link| PE_ACR
    PE_KV -->|Connect| KV
    PE_ACR -->|Connect| ACR
    ACA -->|Via NAT Gateway| NAT
    NAT -->|Outbound HTTPS| RISK

    style AFD fill:#0078d4,stroke:#fff,color:#fff
    style ACA fill:#0078d4,stroke:#fff,color:#fff
    style NAT fill:#4caf50,stroke:#fff,color:#fff
```

## Disaster Recovery Flow

```mermaid
graph LR
    subgraph "Primary Region - East US 2"
        PRIMARY[Container App<br/>Active]
        ACR_PRIMARY[ACR Primary<br/>Geo-Replication]
        KV_PRIMARY[Key Vault<br/>Soft Delete]
    end

    subgraph "Secondary Region - West US 2"
        SECONDARY[Container App<br/>Standby]
        ACR_SECONDARY[ACR Replica<br/>Read-Only]
        KV_BACKUP[Key Vault Backup<br/>Managed Backup]
    end

    subgraph "DR Orchestration"
        AFD_DR[Azure Front Door<br/>Multi-Region Routing]
        MONITOR[Monitoring<br/>Health Probes]
    end

    subgraph "Recovery Process"
        DETECT[Detect Outage<br/>Health Check Fail]
        FAILOVER[Automatic Failover<br/>DNS Update]
        RESTORE[Restore from Backup<br/>Terraform Re-apply]
    end

    PRIMARY -.->|Replicate| ACR_SECONDARY
    KV_PRIMARY -.->|Backup| KV_BACKUP
    AFD_DR -->|Route Traffic| PRIMARY
    AFD_DR -.->|Failover Route| SECONDARY
    MONITOR -->|Health Check| PRIMARY
    MONITOR -->|Trigger| DETECT
    DETECT -->|Initiate| FAILOVER
    FAILOVER -->|Update| AFD_DR
    RESTORE -->|Provision| SECONDARY

    style PRIMARY fill:#4caf50,stroke:#fff,color:#fff
    style SECONDARY fill:#ff9800,stroke:#fff,color:#fff
    style DETECT fill:#f44336,stroke:#fff,color:#fff
```

---

## Diagram Legend

### Color Coding
- **Blue (#0078d4)**: Azure Compute & Networking Services
- **Yellow (#ffb900)**: Security & Secrets
- **Cyan (#00bcf2)**: Monitoring & Observability
- **Green (#4caf50)**: Healthy/Active State
- **Orange (#ff9800)**: Warning/Standby State
- **Red (#f44336)**: Critical/Alert State
- **Purple (#e74c3c)**: External Services

### Icon Meanings
- **Solid Lines**: Active data flow
- **Dashed Lines**: Backup/replication flow
- **Arrows**: Direction of communication

---

*Last Updated: 2026-02-14*
