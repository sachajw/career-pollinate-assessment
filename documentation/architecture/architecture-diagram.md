# Architecture Diagrams

> **Note on scope**: Diagrams marked **[DEPLOYED]** reflect the actual dev environment.
> Diagrams marked **[PRODUCTION TARGET]** describe the intended production architecture — not yet built.

---

## High-Level System Architecture [DEPLOYED]

Current deployed state: `dev` environment, East US 2. No Front Door — traffic enters via Cloudflare proxy to Container App direct ingress.

```mermaid
graph TB
    subgraph "External Systems"
        LOS[Loan Origination System]
        RISK[RiskShield API<br/>api.riskshield.com]
    end

    subgraph "Edge"
        CF[Cloudflare Proxy<br/>DDoS + CDN<br/>finrisk.pangarabbit.com]
    end

    subgraph "Azure - East US 2"
        subgraph "Application Layer"
            ACA[Azure Container Apps<br/>ca-finrisk-dev<br/>Min: 0, Max: 5 replicas]
        end

        subgraph "Security & Secrets"
            KV[Azure Key Vault<br/>kv-finrisk-dev]
            MI[Managed Identity<br/>System-Assigned]
        end

        subgraph "Container Registry"
            ACR[Azure Container Registry<br/>acrfinriskdev<br/>Basic Tier]
        end

        subgraph "Observability"
            AI[Application Insights<br/>appi-finrisk-dev]
            LA[Log Analytics<br/>log-finrisk-dev<br/>30-day retention]
        end
    end

    subgraph "DevOps"
        ADO[Azure DevOps<br/>CI/CD Pipelines]
    end

    LOS -->|HTTPS POST /validate| CF
    CF -->|HTTPS| ACA
    ACA -->|Get Secret via MI| KV
    ACA -->|POST /v1/score| RISK
    ACA -->|Telemetry| AI
    ACA -->|Logs| LA
    MI -.->|RBAC: Key Vault Secrets User| KV
    MI -.->|RBAC: AcrPull| ACR
    ADO -->|Deploy Container| ACA
    ADO -->|Push Images| ACR

    style ACA fill:#0078d4,stroke:#fff,color:#fff
    style KV fill:#ffb900,stroke:#fff,color:#000
    style ACR fill:#0078d4,stroke:#fff,color:#fff
    style AI fill:#00bcf2,stroke:#fff,color:#000
    style CF fill:#f6821f,stroke:#fff,color:#fff
    style RISK fill:#e74c3c,stroke:#fff,color:#fff
```

---

## Deployment Architecture [DEPLOYED]

Single environment (`dev`) deployed. Staging and production environments are not yet provisioned.

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
        DEVENV[Dev Environment<br/>✅ Deployed]
        PRODENV[Production Environment<br/>⬜ Not yet provisioned]
    end

    DEV -->|git push| GIT
    GIT -->|Trigger| BUILD
    BUILD --> SCAN
    SCAN --> PUSH
    PUSH --> INFRA
    INFRA --> DEPLOY
    DEPLOY -->|Auto Deploy| DEVENV
    DEPLOY -->|Manual Gate| PRODENV

    style BUILD fill:#4caf50,stroke:#fff,color:#fff
    style SCAN fill:#ff9800,stroke:#fff,color:#fff
    style DEVENV fill:#4caf50,stroke:#fff,color:#fff
    style PRODENV fill:#9e9e9e,stroke:#fff,color:#fff
```

---

## Data Flow Diagram [DEPLOYED]

```mermaid
sequenceDiagram
    participant Client as Loan System
    participant CF as Cloudflare
    participant API as ca-finrisk-dev
    participant KV as kv-finrisk-dev
    participant RS as RiskShield API
    participant AI as appi-finrisk-dev

    Client->>CF: POST /validate<br/>{firstName, lastName, idNumber}
    CF->>API: HTTPS (Origin Certificate)
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

---

## Security Architecture [DEPLOYED vs TARGET]

```mermaid
graph TB
    subgraph "Implemented in Dev"
        subgraph "Edge Protection"
            CF[Cloudflare Proxy<br/>DDoS + WAF]
            TLS[TLS 1.2+ / HTTPS Only<br/>Cloudflare Origin Certificate]
        end

        subgraph "Identity & Access"
            MI[Managed Identity<br/>System-Assigned, Password-less]
            RBAC[Azure RBAC<br/>Least Privilege]
        end

        subgraph "Application Security"
            INPUT[Input Validation<br/>Pydantic Schema Checks]
            TIMEOUT[Timeout Protection<br/>30s Max]
            RETRY[Retry + Circuit Breaker<br/>3 attempts, exponential backoff]
        end

        subgraph "Data Protection"
            KV[Key Vault Secrets<br/>No env vars, no state files]
            ENCRYPT[Encryption at Rest<br/>Azure-Managed Keys]
        end

        subgraph "Monitoring"
            AUDIT[Audit Logging<br/>All Key Vault access]
            AI[Application Insights<br/>Distributed Tracing]
        end
    end

    subgraph "Production Target Only"
        WAF[Azure Front Door WAF<br/>OWASP Top 10]
        PE[Private Endpoints<br/>Key Vault + ACR]
        VNET[VNet Integration<br/>Network Isolation]
        ROTATE[Secret Rotation Policy<br/>90-day]
    end

    style CF fill:#f6821f,stroke:#fff,color:#fff
    style MI fill:#4caf50,stroke:#fff,color:#fff
    style KV fill:#ffb900,stroke:#fff,color:#000
    style WAF fill:#9e9e9e,stroke:#fff,color:#fff
    style PE fill:#9e9e9e,stroke:#fff,color:#fff
    style VNET fill:#9e9e9e,stroke:#fff,color:#fff
    style ROTATE fill:#9e9e9e,stroke:#fff,color:#fff
```

---

## Infrastructure Components [DEPLOYED]

Actual deployed resources in `rg-finrisk-dev`, East US 2.

```mermaid
graph TB
    subgraph "Resource Group: rg-finrisk-dev"
        subgraph "Compute"
            ACA[Container App<br/>ca-finrisk-dev<br/>Min: 0, Max: 5 replicas]
            CAE[Container App Environment<br/>cae-finrisk-dev]
        end

        subgraph "Registry"
            ACR[Container Registry<br/>acrfinriskdev<br/>Basic Tier]
        end

        subgraph "Security"
            KV[Key Vault<br/>kv-finrisk-dev<br/>Standard, Soft Delete 90d]
            MI[Managed Identity<br/>System-Assigned]
        end

        subgraph "Monitoring"
            LA[Log Analytics<br/>log-finrisk-dev<br/>30-day Retention]
            AI[Application Insights<br/>appi-finrisk-dev]
        end
    end

    ACA -->|Runs in| CAE
    ACA -->|Uses| MI
    ACA -->|Pulls Images| ACR
    ACA -->|Reads Secrets| KV
    ACA -->|Sends Logs| LA
    ACA -->|Sends Telemetry| AI
    MI -.->|AcrPull| ACR
    MI -.->|Key Vault Secrets User| KV
    CAE -->|Streams Logs| LA

    style ACA fill:#0078d4,stroke:#fff,color:#fff
    style KV fill:#ffb900,stroke:#fff,color:#000
    style LA fill:#00bcf2,stroke:#fff,color:#000
    style AI fill:#00bcf2,stroke:#fff,color:#000
```

---

## Network Architecture [PRODUCTION TARGET]

Planned production topology. Not yet deployed.

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
            ACR[Container Registry<br/>Premium + Geo-Replication]
        end
    end

    subgraph "External Services"
        RISK[RiskShield API]
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

---

## Disaster Recovery [PRODUCTION TARGET]

Planned multi-region topology. Not yet deployed.

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
        KV_BACKUP[Key Vault Backup]
    end

    subgraph "DR Orchestration"
        AFD_DR[Azure Front Door<br/>Multi-Region Routing]
        MONITOR[Monitoring<br/>Health Probes]
    end

    PRIMARY -.->|Replicate| ACR_SECONDARY
    KV_PRIMARY -.->|Backup| KV_BACKUP
    AFD_DR -->|Route Traffic| PRIMARY
    AFD_DR -.->|Failover Route| SECONDARY
    MONITOR -->|Health Check| PRIMARY
    MONITOR -.->|Trigger Failover| AFD_DR

    style PRIMARY fill:#4caf50,stroke:#fff,color:#fff
    style SECONDARY fill:#9e9e9e,stroke:#fff,color:#fff
```

---

## Diagram Legend

### Status Labels
- **[DEPLOYED]**: Reflects the actual `dev` environment as built
- **[PRODUCTION TARGET]**: Intended future architecture, not yet provisioned

### Color Coding
- **Blue (#0078d4)**: Azure Compute & Networking
- **Yellow (#ffb900)**: Security & Secrets
- **Cyan (#00bcf2)**: Monitoring & Observability
- **Orange (#f6821f)**: Cloudflare
- **Green (#4caf50)**: Healthy / Active
- **Grey (#9e9e9e)**: Not yet deployed
- **Red (#e74c3c)**: External Services

### Line Styles
- **Solid lines**: Active data flow
- **Dashed lines**: RBAC relationships / replication / failover paths

---

*Last Updated: 2026-02-17*
