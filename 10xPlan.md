Great questions. Short answer: the **single repo is for real deployments**, not just study—and the docs (One-Pager + Runbook) are the “brains” you use to design and operate what you deploy.

Below I’ll (1) clarify how the monorepo deploys to k8s, (2) show you exactly how to use the **Systems Design One-Pager**, and (3) give you a concrete **Runbook** with examples you can copy.

---

# 1) Single repo: study AND production—here’s how it actually deploys

## Why one repo?

- **Tight feedback loop:** API, trainers, batch jobs, infra, and docs evolve together.
    
- **Shared CI/CD:** consistent lint/test/build/release rules across components.
    
- **Interview-ready:** reviewers see “from Terraform to Helm to app code” in one place.
    

## Typical structure (recap)

```
genai-stack/
  apps/
    api/         # FastAPI service (RAG + backend endpoints)
    batch/       # k8s CronJobs (batch scoring, cleanup)
    trainers/    # PyTorch/Optuna training jobs
  infra/
    terraform/   # VPC, EKS, RDS, S3, SQS, IAM (IaC)
    k8s/         # Helm charts OR Kustomize overlays per env
      base/
      overlays/
        dev/
        staging/
        prod/
  docs/
    designs/     # one-pagers + diagrams
    runbooks/    # on-call docs per service
  .github/workflows/
  ENGINEERING_LOG.md
  README.md
```

## Deploy model (k8s-first with EKS)

- **Images**: Each app builds its own Docker image, tagged by commit SHA (e.g., `api:sha-abcdef`).
    
- **Manifests**: Use **Helm** or **Kustomize** with per-env overlays (`dev/staging/prod`) to set replicas, resources, secrets, URLs.
    
- **CI/CD**:
    
    - On PR: lint + tests + build images (but don’t deploy).
        
    - On merge to `main`: deploy to **dev**.
        
    - On a git tag like `vX.Y.Z`: deploy to **staging**; manual approval → **prod**.
        
- **Infra**: Terraform runs in its **own workflow** (and ideally its own remote state). You don’t deploy infra every commit; you apply it when you change infra code.
    

## Environments (simple, safe)

- **dev**: free to auto-deploy on merge; low SLO.
    
- **staging**: mirrors prod size/config where feasible; used for load/canary.
    
- **prod**: manual approval gate, blue/green or canary.
    

## Pros & caution

- **Pros:** velocity, consistency, visibility.
    
- **Caution:** keep **infra changes** gated; use code owners; protect prod with manual approvals and small canaries.
    

Bottom line: you are absolutely **deploying from this repo**—containers to EKS, manifests from `infra/k8s/overlays/*`, with CI/CD doing the work.

---

# 2) Systems Design One-Pager — how to use it (and a filled example)

**What it is:** a single Markdown page you write **before** building (or during an interview drill). It forces clarity on requirements, interfaces, data, scaling, and failure modes.

**When to write one:**

- New service or major change (e.g., adding SQS + idempotency).
    
- Before you start a week’s milestone.
    
- For interview practice (45-min timer → one page).
    

**How to use it:** fill each section in 1–4 bullets. Avoid essays. If you can’t fill a section, that’s a red flag you need to research.

### Template (copy into `docs/designs/<service>-<yyyymmdd>.md`)

- **Context & Goals**
    
- **Constraints & Assumptions**
    
- **APIs & SLAs**
    
- **High-Level Diagram**
    
- **Data Model & Indexes**
    
- **Scaling & Caching**
    
- **Queues & Backpressure**
    
- **Consistency & Transactions**
    
- **Observability**
    
- **Failure Modes & Mitigations**
    
- **Capacity & Cost (napkin math)**
    
- **Rollout & DR (RPO/RTO)**
    
- **Risks & Alternatives**
    
- **Decision (TL;DR)**
    

### Example (RAG Service One-Pager — condensed)

**Context & Goals**

- Provide question-answering over internal docs via REST API.
    
- Initial target: p95 latency ≤ 800ms, 99.5% availability, cost ≤ $X/1k queries.
    

**Constraints & Assumptions**

- EKS on AWS; Postgres with `pgvector`; Redis available; traffic spiky (daytime peaks).
    
- Content size ≈ 50k chunks (avg 800 tokens).
    

**APIs & SLAs**

- `POST /v1/query` → `{query, user_id}` → `{answer, citations, latency_ms}`; p95 ≤ 800ms.
    
- `POST /v1/ingest` (authz required) → bulk docs.
    

**High-Level Diagram (text)**  
Client → Ingress → API Pods → (Redis cache) → Embedding/Vector DB (pgvector) → LLM provider  
↘ Postgres (metadata)  
↘ SQS (async long-running)

**Data Model & Indexes**

- `documents(id, source, created_at)`
    
- `chunks(id, doc_id, text, embedding VECTOR(768), created_at)` → index on `embedding` + `doc_id`.
    
- `queries(id, user_id, q, latency_ms, cost, created_at)` → B-tree on `created_at` and `user_id`.
    

**Scaling & Caching**

- HPA on CPU + custom latency metric.
    
- Redis cache: key=`hash(query)`, TTL 10–30m with jitter; stale-while-revalidate for hot keys.
    

**Queues & Backpressure**

- SQS for ingestion & re-embedding; consumers with idempotency keys; DLQ for poison messages.
    

**Consistency & Transactions**

- Ingestion: write doc + chunks in one transaction.
    
- Query path: read-committed OK; eventual consistency acceptable for newly ingested docs.
    

**Observability**

- OpenTelemetry traces: `query_id` spans across API → DB → LLM.
    
- Prometheus: QPS, p95/99 latency, timeout rate, token usage, cost per request.
    

**Failure Modes & Mitigations**

- LLM timeouts → circuit breaker + retry with lower context.
    
- Hot partition in Redis → sharding, per-key locks.
    
- DB bloat → autovacuum, partitioning by `created_at`.
    

**Capacity & Cost (napkin)**

- Peak 100 RPS; avg tokens per request ~1.5k; nightly batch ingest ~10k chunks.
    
- Compute: 6 × `api` pods (500m CPU/1Gi) to hit SLO; Redis `cache.t3.small`. (Adjust after k6 data.)
    

**Rollout & DR**

- Canary 5% → 25% → 100%; health checks & error budget watch.
    
- RPO: 15 min backups; RTO: 30 min restore (multi-AZ RDS).
    

**Risks & Alternatives**

- Risk: LLM latency volatility → consider local reranker + smaller context windows.
    
- Alt: OpenSearch instead of pgvector for hybrid search.
    

**Decision**

- Proceed with pgvector + Redis + SQS; build evals & caching first to control latency/cost.
    

That’s it. One page. Now you (and reviewers/interviewers) know exactly what you’re building and why.

---

# 3) Runbook — what it is and a practical example

**What it is:** the **on-call manual** for a service. When something breaks, this doc tells you exactly what to check and how to fix it—fast.

**When to create:** as soon as a service is deployed (even “Hello World” + DB). Update it after every incident.

**Where:** `docs/runbooks/<service>.md`

### Runbook Template

**Overview**

- Purpose, owner(s), Slack/Email, repo path, last updated.
    

**SLOs & Error Budget**

- Availability, p95 latency, max error rate.
    

**Dashboards & Logs**

- Links to Grafana/CloudWatch/Kibana; names of key charts.
    

**Alerts (what they mean, what to do)**

- Alert name → common causes → triage steps → escalation.
    

**Standard Operating Procedures**

- High CPU, pod crash loops, queue backlog, DB connection spikes, elevated 5xx, cache stampede.
    

**Diagnostics (copy-paste snippets)**

- `kubectl`/`aws` commands, SQL to check slow queries, Redis keys to inspect.
    

**Rollbacks & Feature Flags**

- How to roll back to previous image; how to disable risky features.
    

**Deploy/Release**

- Canary playbook, manual approval checklist, smoke test steps.
    

**DR/Backups**

- Backup schedule, restore steps, RPO/RTO, failover command.
    

**Security & Access**

- Secrets locations, on-call permissions, break-glass account procedure.
    

**Known Issues**

- “If X happens, it’s probably Y; here’s the fix.”
    

### Example Runbook (RAG API — condensed)

**Overview**

- **Service:** RAG API (`apps/api`)
    
- **Owners:** You (@handle)
    
- **Cluster:** `eks-prod-us-east-1`
    
- **Last updated:** 2025-10-02
    

**SLOs & Error Budget**

- Availability ≥ 99.5% monthly
    
- p95 latency ≤ 800ms
    
- Error rate ≤ 0.5%
    

**Dashboards & Logs**

- Grafana: `RAG-API/Latency`, `RAG-API/QPS`, `RAG-API/5xx`, `Token-Costs`.
    
- Traces: `service.name=rag-api`.
    
- Logs: `kubectl logs -l app=rag-api -n prod -f`.
    

**Alerts**

- **High p95 (>800ms for 10m)** → Check LLM provider status; reduce context size via `FEATURE_CONTEXT_LIMIT=small`; verify cache hit rate > 60%.
    
- **5xx > 1% for 5m** → Inspect recent deploys; roll back (see below); check DB connections (`SELECT * FROM pg_stat_activity`).
    
- **Queue Backlog > 10k** → Scale consumer replicas (`kubectl scale deploy rag-consumer --replicas=...`); inspect DLQ; check SQS visibility timeout.
    

**Diagnostics (snippets)**

```bash
# pods and restarts
kubectl -n prod get pods -l app=rag-api
kubectl -n prod describe pod <pod>

# HPA status
kubectl -n prod get hpa rag-api

# Redis hot keys (example placeholder)
redis-cli --scan --pattern "query:*" | head

# Postgres slow queries (example)
SELECT pid, query, now()-query_start AS runtime
FROM pg_stat_activity
WHERE state='active' AND now()-query_start > interval '2 minutes';
```

**Rollbacks & Feature Flags**

- **Deploy history:** View in CI `rag-api` job → pick last green SHA.
    
- **Rollback:** `helm -n prod rollback rag-api <REVISION>` (or `kubectl set image`).
    
- **Flags:** Set `FEATURE_RERANKER=false` to disable reranking path.
    

**Deploy/Release**

- Canary 5% traffic → watch `Latency & 5xx` for 10m → 25% for 10m → 100%.
    
- Smoke tests: `/health`, 3 canned queries with expected citation counts.
    

**DR/Backups**

- RDS automated backups daily; snapshot retention 7 days.
    
- **Restore:** create new RDS from latest snapshot → update secret/DSN → rolling restart.
    
- **RPO:** 15 min; **RTO:** 30 min.
    

**Security & Access**

- Secrets in AWS Secrets Manager: `prod/rag-api/*`.
    
- On-call has read access to logs/metrics and `kubectl` in `prod` namespace.
    

**Known Issues**

- Redis node overload → increase memory, add TTL jitter, enable request coalescing.
    
- LLM provider spikes latency → switch to backup model; reduce prompt size by 30%.
    

That’s a real, usable runbook. If paged at 2am, you’ll be glad it exists.

---

## TL;DR next actions for you

1. Keep the **single repo**—it **deploys** your services to EKS with CI/CD and per-env overlays.
    
2. For your next milestone, create a **Systems Design One-Pager** first (use the example above).
    
3. As soon as your API is live in **dev**, add a **Runbook** (copy the template) and update it every time you fix something.
    

If you want, I can drop **ready-to-use Markdown templates** for the One-Pager and Runbook into your canvas, plus a skeleton **Helm/Kustomize** layout and a **GitHub Actions** workflow you can paste in and run.