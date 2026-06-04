# ACMF Reference Architecture Diagrams

These diagrams are the canonical visuals for the ACMF methodology. They
render natively on GitHub via Mermaid — no external image hosting, no
broken links over time.

If you change the methodology, change the diagram in the same PR. Out-of-date
visuals are worse than no visuals.

## 1. ACMF five-phase overview

The end-to-end shape of an engagement, from kickoff to case study. Agents
run inside Phase 1 and (optionally) Phase 4; every other box is a human
decision or deliverable.

```mermaid
flowchart LR
    subgraph P1["Phase 1 · Assess"]
        D[Discovery] --> A1((Agent run))
        A1 --> B[discovery-bundle.json]
        B --> R1[Assessment Report]
    end
    subgraph P2["Phase 2 · Mobilize"]
        R1 --> W[Wave Plan]
        W --> LZ[Landing Zone IaC]
    end
    subgraph P3["Phase 3 · Migrate"]
        LZ --> CO[Per-wave Cutover]
        CO --> V[Validate SLOs]
        V --> GO{Go / No-Go}
        GO -->|rollback| CO
        GO -->|next wave| CO
    end
    subgraph P4["Phase 4 · Modernize"]
        GO -->|all done| OPT[Right-size · GitOps · Pod Identity]
        OPT -.optional.-> A2((Persistent agent))
    end
    subgraph P5["Phase 5 · Document"]
        OPT --> CS[Case Study + Lessons Learned]
    end

    classDef agent fill:#fff4e6,stroke:#d97706,stroke-width:2px;
    class A1,A2 agent;
```

**Reading guide:** Boxes in orange are agent-run; everything else is
human-authored or human-judged. The dashed arrow into Phase 4 is the only
optional persistent agent in the framework, and it is opt-in per
[`docs/CONSTITUTION.md`](../CONSTITUTION.md).

## 2. Source/target adapter model

ACMF normalises every source platform into a single discovery-bundle schema,
then the target adapters consume that schema to emit AWS-specific manifests
and IaC. Adding a new source or target is a matter of writing one adapter,
not rewriting the methodology.

```mermaid
flowchart LR
    subgraph SRC["Source Adapters"]
        AV[GKE Enterprise on VMware]
        AB[GKE Enterprise on Bare Metal]
        AG[GKE Enterprise on GCP]
        OS[OpenShift]
        RC[Rancher]
        VK[Vanilla K8s]
    end

    SCH[(discovery-bundle.json<br/>schema v0.2.0)]:::schema

    subgraph TGT["Target Adapters"]
        EKS[Amazon EKS]
        ECS[Amazon ECS]
    end

    AV --> SCH
    AB --> SCH
    AG --> SCH
    OS --> SCH
    RC --> SCH
    VK --> SCH
    SCH --> EKS
    SCH --> ECS

    classDef default fill:#dcfce7,stroke:#16a34a,stroke-width:2px;
    classDef schema fill:#dbeafe,stroke:#1d4ed8,stroke-width:2px;
    classDef target fill:#fef9c3,stroke:#ca8a04,stroke-width:2px;
    class EKS,ECS target;
```

**Reading guide:** All 6 source adapters and both target adapters are shipped.
The schema in the centre is the contract — adapters change independently as
long as they read or write the schema. See [`ROADMAP.md`](../../ROADMAP.md)
for future adapters (AKS, Nomad).

## 3. Discovery architecture (Phase 1 detail)

The trust boundary the customer cares about: nothing leaves the customer
environment unless they ship it. The agent runs once, writes a JSON file,
and exits.

```mermaid
flowchart TB
    subgraph CUST["Customer Environment"]
        K[Source Cluster] --> AG((Agent / Script))
        AG --> BUN[discovery-bundle.json]
        BUN --> H[Customer Reviews + Approves]
    end

    LLM{{LLM Endpoint<br/>Bedrock / self-hosted}}
    AG <-.prompt + structured output.-> LLM

    DEL[Delivery Side]
    H -.encrypted, customer-initiated.-> DEL

    classDef trust fill:#fef3c7,stroke:#b45309;
    classDef ext fill:#fee2e2,stroke:#991b1b,stroke-dasharray:4 3;
    class CUST trust;
    class LLM,DEL ext;
```

**Reading guide:** The yellow box is the customer perimeter. Only two arrows
cross it: (a) the LLM call, against an endpoint the customer chose; (b) the
bundle handoff, encrypted and customer-initiated. There is no phone-home
channel and no persistent agent. See FAQ §"Security & data handling".

## 4. Phase 3 — progressive traffic shift

Per-wave cutover pattern. Source and target run in parallel behind a shared
mesh (or DNS) until weight reaches 100% on the target and the wave is
declared done. Rollback is "set weight back to 0%."

```mermaid
flowchart LR
    U((User)) --> GW[Edge Gateway<br/>Route 53 weighted / mesh]

    subgraph SRC2["Source"]
        SVC1[svc.payments.v1]
        WL1[Workload pods]
        SVC1 --> WL1
    end

    subgraph TGT2["Target (EKS / ECS)"]
        SVC2[svc.payments.v1]
        WL2[Workload pods]
        SVC2 --> WL2
    end

    GW -- "90% → 50% → 0%" --> SVC1
    GW -- "10% → 50% → 100%" --> SVC2

    DB[(Shared Data Plane<br/>RDS / DMS replication)]
    WL1 --> DB
    WL2 --> DB

    classDef src fill:#fee2e2,stroke:#b91c1c;
    classDef tgt fill:#dcfce7,stroke:#15803d;
    class SRC2 src;
    class TGT2 tgt;
```

**Reading guide:** Both sides talk to the same data plane during the shift —
that's why data-migration patterns
([`docs/decisions/data-migration-patterns.md`](../decisions/data-migration-patterns.md))
must be settled in Phase 2, not Phase 3. Rollback is a weight change, not
a redeploy.

## 5. Target selection decision tree

The first decision per workload: EKS or ECS? Then which compute model?

```mermaid
flowchart TD
    W[Workload] --> Q1{Uses K8s API?}
    Q1 -->|Yes| EKS[→ EKS]:::eks
    Q1 -->|No| ECS[→ ECS]:::ecs
    Q1 -->|Mixed| HY[→ Hybrid]:::hy

    EKS --> Q2{Compute model}
    Q2 --> AM[Auto Mode]
    Q2 --> KP[Karpenter]
    Q2 --> MNG[Managed Node Groups]
    Q2 --> FP[Fargate Profiles]

    ECS --> Q3{Launch type}
    Q3 --> FG[Fargate]
    Q3 --> SP[Fargate Spot]
    Q3 --> EC[EC2]

    classDef eks fill:#dcfce7,stroke:#16a34a,stroke-width:2px;
    classDef ecs fill:#dbeafe,stroke:#2563eb,stroke-width:2px;
    classDef hy fill:#fef9c3,stroke:#ca8a04,stroke-width:2px;
```

**Reading guide:** The top-level question is binary — if any workload uses
CRDs, operators, Helm, or mesh CRDs, it stays on EKS. See
[`docs/decisions/ecs-vs-eks.md`](../decisions/ecs-vs-eks.md) for the full
3-level decision tree with cost data.

---

## How to update these

1. Edit the Mermaid block(s) in this file.
2. Verify rendering on GitHub by viewing the file in the PR preview.
3. If you add a new diagram, link it from the README and the
   [`acmf-overview-1pager.md`](../customer-facing/acmf-overview-1pager.md).
4. Keep diagrams under ~25 nodes each — past that, split into a sub-diagram.
