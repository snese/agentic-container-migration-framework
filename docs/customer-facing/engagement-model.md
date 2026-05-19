# ACMF Engagement Model

> **The #1 unanswered customer question is "how much does this cost and how
> long does it take?"** This page gives you four shapes to pick from, and
> the rough scope/timeline/owner/MAP-eligibility for each. Specifics are
> always scoped per customer; the table below is the framework, not a quote.

## Pick the shape that fits

| Engagement shape | Scope | Timeline | Who delivers | MAP eligible? |
|---|---|---|---|---|
| **Self-service** (Discovery Options 1–2) | Customer runs the manifest-only or self-export bash flow, reads the playbooks, executes Phase 1–3 with their own platform team. AWS field is hands-off. | **2–4 weeks** for Assess + a draft wave plan; Migrate timeline depends on customer execution. | Customer platform team. ACMF repo is the deliverable. | **No** — no AWS-side delivery to fund. Customer can still use MAP credits separately for AWS consumption. |
| **SA-assisted** (Discovery Options 3–4) | AWS Solutions Architect runs the agentic discovery against customer-supplied read-only credentials, walks the customer through the assessment + wave plan, hands execution back to the customer team. | **4–8 weeks** through Mobilize; Migrate cutovers customer-led with SA office hours. | AWS SA + customer platform team (joint). | **Potentially**, as a **MAP Assess** engagement. Talk to your MAP PM. |
| **ProServe-delivered** | AWS Professional Services scopes a full Assess → Migrate → Modernize program using ACMF as the methodology. ProServe team co-delivers cutovers, owns landing-zone IaC, runs the wave plan. | **12–24 weeks** end-to-end; longer if cutover risk requires a slow shift. | AWS ProServe + customer team. | **Yes** — maps cleanly to **MAP Mobilize + Migrate**. |
| **Partner-delivered** | A qualified Migration / Containers Competency Partner (SI) uses ACMF as their delivery methodology. Customer signs the partner's SOW; AWS field stays advisory. | Varies by partner, typically **12–20 weeks**. | SI partner + customer team. AWS field optional. | **Yes** — through the partner's MAP funding path. |

## How to self-identify

Pick the shape based on three answers:

1. **Who has the K8s expertise?**
   - Strong customer platform team → Self-service or SA-assisted.
   - Thin team or no in-house K8s experience → ProServe or Partner.
2. **What's the policy posture?**
   - Air-gapped, regulated, or sovereign → Discovery Option 2 (self-service)
     or Option 3 with a partner that already has the security clearance.
   - Standard enterprise → any option works.
3. **What MAP funding stage are you in?**
   - No MAP yet → ACMF Assess deliverables also satisfy the MRA gate that
     unlocks MAP funding. Self-service or SA-assisted is the right entry.
   - MAP Assess approved → SA-assisted or ProServe.
   - MAP Mobilize/Migrate approved → ProServe or Partner.

## What "delivery owner" actually means

| Owner | What they sign for | What they don't |
|---|---|---|
| Customer platform team | Cluster access, cutover go/no-go, post-migration ops, prod incidents. | Landing-zone IaC quality, target-service decisions if SA/ProServe is on the engagement. |
| AWS SA | Methodology fidelity, target-service recommendations, MAP MRA artifact quality. | Cutover execution, incident response, customer prod data. |
| AWS ProServe | End-to-end delivery, including landing zone, cutover playbooks, post-migration handoff. | Long-term ops (that's customer + partner). |
| SI Partner | Same surface as ProServe, scoped through partner's SOW. | Anything the partner SOW excludes — read it carefully. |

## What you walk away with (regardless of shape)

The ACMF deliverable list does not change between shapes — only who produces
each artifact does:

- `discovery-bundle.json` (schema-valid)
- `readiness-scorecard.md` (MRA across all six CAF perspectives)
- `assessment-report.md` + `target-mapping.yaml`
- `wave-plan.md` + `waves.yaml` (with rollback per wave)
- `iac-skeleton/` (Terraform or CDK)
- `cutover-log.md` per wave during Migrate
- An anonymised case study (with customer approval) — feeds the next engagement

Per [ACMF Constitution](../CONSTITUTION.md) Principle 6 — *every engagement
produces artifacts the customer keeps, not a black-box service.*

## Pricing — what we will and won't say

ACMF the framework is **free and open** (no per-seat license, no SaaS
endpoint). The cost of an engagement is **delivery effort + your AWS
consumption**, both scoped per customer.

What we will tell you up front:

- **Self-service:** $0 framework cost. Engineering hours are yours.
- **SA-assisted:** No engagement fee from AWS for MAP-aligned Assess; standard
  AWS field engagement model otherwise.
- **ProServe / Partner:** Quoted by scope (cluster count × workload count ×
  cutover risk), discounted under MAP funding when applicable.

What we won't quote on this page:

- Specific dollar figures — they're a function of your estate, your timeline,
  and the partner. Anything we put here would be wrong for someone.
- Per-workload pricing — ACMF charges by engagement, not by workload.
- AWS infrastructure cost — use the [AWS Pricing Calculator](https://calculator.aws/)
  with the target-mapping output for an accurate number.

## Cross-references

- [Customer FAQ — pricing & commercial section](./acmf-customer-faq.md#pricing--commercial)
- [Pitch guide — when to bring up which shape](./acmf-pitch-guide.md)
- [Discovery options menu](../prerequisites.md)
- [ACMF Constitution](../CONSTITUTION.md)

---

*Hung-Che Lo · `hclo@snese.net` · open an issue if your scenario doesn't fit one of these four shapes.*
