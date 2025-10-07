---
# 0
---
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


---
# 1
---
# Your 12‑Week 10× Engineer Playbook (GenAI‑Focused)

You said this can change four people’s lives. I wrote this as a **complete, end‑to‑end plan** you can start today—optimized for a full‑time job (2×60‑min deep‑work blocks), k8s‑first deployments, GenAI emphasis, and **visible outcomes** that get you hired fast.

---

## What “10×” Looks Like (Outcome Targets)

By Week 12 you will have:

1. **Three production‑quality portfolio systems** (deployed, load‑tested, monitored):
    
    - **GenAI RAG service** with evals, guardrails, caching, and cost/latency dashboards.
        
    - **Tabular ML pipeline**: train → tune (Optuna) → track (MLflow) → batch scoring job → deploy.
        
    - **Resilient backend API**: Postgres, Redis, queues, tracing, CI/CD, runbook.
        
2. **Interview‑ready systems design** mental models (scaling, data, queues, indexes, consistency, DR).
    
3. **Delivery habits**: 2×60‑min deep work daily, weekly demo cadence, one‑pager design docs, runbooks.
    
4. **Confidence** through repetition: Anki decks for AWS, System Design, ML (5 new cards/day, daily reviews).
    

**Why this works:** It blends **visible shipped systems** (what recruiters trust), **fundamentals** (what senior engineers test), and **habits** (what sustains output). That triangle is the fastest path to “10×”.

---

## Daily Plan (built for a full‑time job)

**Morning**

- Hydrate & stretch → **30–45 min exercise** (strength or cardio).
    
- **Deep Work #1 (60 min):** Core build/learning for the week’s milestone.
    

**Afternoon/After Work**

- 10–20 min walk.
    
- **Deep Work #2 (60 min):** Tests, docs, refactors, polish; small demoable increment.
    

**Evening**

- Add **5 Anki cards** (AWS, System Design, ML); do reviews (10–15 min).
    
- 20–30 min reading (docs/blogs/papers) and a 2–3 line reflection.
    

**Non‑negotiables:** phone on Do Not Disturb, timer on, work in a quiet space, Git commit each session.

---

## Weekly Rhythm

- **Mon (15m):** Define one Friday demo (small but deployable).
    
- **Wed (15m):** Mid‑week checkpoint; cut scope to protect the Friday demo.
    
- **Fri (≤20m):** Record demo video (screen + voice) and update README.
    
- **Sun (20m):** Weekly review: lessons learned, blockers, add 5 flashcards, pick next target.
    

---

## Portfolio Systems (Blueprints)

### 1) GenAI RAG Service

- **Stack:** FastAPI, pgvector (or OpenSearch), sentence‑transformers, OpenAI/Bedrock, Redis, EKS (k8s), Terraform, OpenTelemetry, Prometheus/Grafana, k6.
    
- **Must‑haves:** Evals (faithfulness/relevance), guardrails (PII/toxicity), caching (TTL + stampede protection), cost/latency dashboards, rate limiting, auth (JWT).
    

### 2) ML Tabular Pipeline

- **Stack:** PyTorch (starter MLP), scikit‑learn utilities, MLflow, Optuna, S3, batch scoring job (CronJob on k8s), Postgres, CI for training + deployment.
    
- **Must‑haves:** Proper splits, tracked runs, artifact versioning, automated best‑run selection and rollback.
    

### 3) Resilient Backend API

- **Stack:** FastAPI, Postgres (SQLAlchemy + Alembic), Redis, SQS (or Kafka), NGINX/Ingress, HPA, blue/green or canary rollouts, OpenTelemetry tracing.
    
- **Must‑haves:** Idempotent writes, retries/backoff, pagination, structured logging, SLOs/alerts, runbook.
    

---

## Repo Structure (single mono‑repo)

```
genai-stack/
  apps/
    api/            # FastAPI app (RAG + backend endpoints)
    batch/          # ML batch scoring jobs
    trainers/       # PyTorch/Optuna training
  infra/
    terraform/      # VPC, EKS, RDS, S3, SQS, IAM, etc.
    k8s/            # Helm charts / manifests: Deployments, Services, Ingress, HPA
  docs/
    designs/        # one‑pagers & ADRs
    runbooks/
  scripts/
  ENGINEERING_LOG.md
  README.md
```

---

## 12‑Week Roadmap (k8s‑first, 2×60‑min/day)

> Each week ends with a **deployed demo** and a short video.

### Weeks 1–3: Cloud & Backend Foundations

**Goals:** Own an end‑to‑end service with DB, cache, traces, and basic scaling.

- **Backend API**: FastAPI endpoints (CRUD + `/query`), Pydantic validation, JWT auth, Redis rate limiting; pytest.
    
- **Data Layer**: Postgres schema, indexing (B‑tree, partial), Alembic migrations, read‑replica concept.
    
- **k8s on EKS**: Deployment with liveness/readiness probes; Service/Ingress; ConfigMaps/Secrets; basic RBAC; HPA.
    
- **Infra as Code (Terraform)**: VPC, EKS cluster/node groups, RDS Postgres, S3, SQS, IAM, CloudWatch.
    
- **Observability & Load**: OpenTelemetry traces; Prometheus/Grafana dashboards; k6 load test; set latency SLO.  
    **Deliverable (end of W3):** “Hello RAG” API live on EKS with Postgres/Redis, tracing, basic HPA, k6 report.
    

### Weeks 4–6: ML You Can Defend (Train, Tune, Ship)

**Goals:** Move from “took courses” to “I train, tune, and deploy.”

- **Project A (Tabular)**: PyTorch MLP; clean train/val/test; MLflow tracking to S3; Optuna HPO; model registry.
    
- **Batch Scoring**: k8s CronJob writes predictions to Postgres; versioned artifacts; rollback procedure.
    
- **Project B (GenAI Evals)**: RAG pipeline (ingest → embeddings → vector search → answer); offline evals (faithfulness/relevance); A/B prompt tests; guardrails; caching to cut cost/latency.  
    **Deliverable (end of W6):** MLflow runs + Optuna study + automated deploy of the best run; RAG eval harness wired to CI.
    

### Weeks 7–9: Systems Design Muscles (Reliability at Scale)

**Goals:** Demonstrate architectural judgment with failures and queues.

- **Scaling the GenAI API**: Add SQS for async jobs; implement idempotency keys; retries with exponential backoff; DLQ.
    
- **Caching & Search**: Redis with TTL and stampede protection; optional hybrid search (BM25 + vector via OpenSearch).
    
- **Failure‑testing**: Chaos experiments (kill pods, throttle DB, enforce timeouts);
    
- **Runbook**: `RUNBOOK.md` with dashboards, alerts, common remediations; RPO/RTO targets.
    
- **Design One‑Pagers (3)**: “Multi‑tenant GenAI platform,” “RAG service @ 10k rps,” “Feature store for fraud.”  
    **Deliverable (end of W9):** Updated architecture diagram; chaos test notes; three polished one‑pagers.
    

### Weeks 10–12: Polish, Product Thinking, Interviews

**Goals:** Package your work for hiring managers & land offers.

- **DX & Productization**: Small Python client SDK (retries, metrics); cost/latency dashboard; ADRs for key choices.
    
- **Interview Drills**: 3 system‑design prompts/week (45‑min timer → one‑pager); ML theory drills (leakage, bias/variance, evals, drift); behavioral stories tied to your demos.
    
- **Portfolio & Branding**: Public (or invite‑only) GitHub; 3 short demo videos; README index as portfolio; LinkedIn headline: “ML/GenAI Platform Engineer — k8s‑deployed RAG with evals, tuned models, Terraform IaC.”  
    **Deliverable (end of W12):** Recruiter‑friendly portfolio, demo videos, resume refresh aligned to shipped artifacts.
    

---

## What to Search (Targeted Keywords so You Never Wander)

- **Cloud/k8s/AWS:** “EKS Deployment yaml readiness probe”, “Terraform EKS module example”, “VPC subnets public vs private”, “IAM least privilege pattern”, “k8s HPA example”.
    
- **Backend:** “FastAPI JWT auth example”, “SQLAlchemy Alembic migrations”, “Redis rate limiting pattern”, “Idempotency keys API design”, “Circuit breaker retries backoff”.
    
- **ML:** “PyTorch tabular classification example”, “Optuna with MLflow tutorial”, “MLflow model registry S3”, “Data drift monitoring sklearn”.
    
- **System Design:** “Load balancer vs reverse proxy”, “DB sharding vs replication”, “SQS visibility timeout and DLQ”, “Cache stampede prevention”.
    

---

## Anki: Spaced Repetition That Sticks

- **Decks:** 1) AWS, 2) System Design, 3) ML.
    
- **Cadence:** Add **5 cards/day** from what you built/read. Review daily (10–15 min). After ~90 days → ~450 custom, relevant cards.
    
- **Card Patterns:**
    
    - **Definition:** Q: “What is an EKS readiness probe used for?” → A: “Signals when pod can receive traffic; gates Ingress/Service routing.”
        
    - **Trade‑off:** Q: “ECS vs EKS?” → A: “ECS simpler AWS orchestration; EKS portable Kubernetes; EKS more control but more ops.”
        
    - **Procedure:** Q: “Steps to safe DB migration?” → A: “Shadow tables → dual‑writes → backfill → cutover → rollback plan.”
        
- **Starter 9 Cards (copy into Anki today):**
    
    - **AWS**
        
        1. Q: “Public vs private subnet?” → A: “Public has route to IGW; private routes via NAT; DBs usually in private.”
            
        2. Q: “What does an IAM policy’s least privilege mean?” → A: “Grant only required actions/resources; deny by default; narrow conditions.”
            
        3. Q: “HPA scales based on what?” → A: “Metrics (CPU/memory/custom); adjusts replica count to meet targets.”
            
    - **System Design**  
        4. Q: “Idempotency key purpose?” → A: “Client‑supplied key makes retries safe—server dedupes duplicate requests.”  
        5. Q: “Read replica vs shard?” → A: “Replica scales reads and adds failover; sharding splits data horizontally for size/throughput.”  
        6. Q: “Cache stampede fix?” → A: “TTL jitter, request coalescing, stale‑while‑revalidate, per‑key locks.”
        
    - **ML**  
        7. Q: “What does Optuna Trial track?” → A: “Hyperparams + objective for a run; enables pruning/early stopping.”  
        8. Q: “Data leakage example?” → A: “Using target‑influenced features at train time (e.g., future info); inflates metrics, fails in prod.”  
        9. Q: “MLflow stores what?” → A: “Params, metrics, artifacts, models; enables experiment tracking & reproducibility.”
        

---

## Systems Design One‑Pager Template (use for every design)

**Context & Constraints** → **API/SLAs** → **High‑level Diagram** → **Data Model & Indexes** → **Scaling & Caching** → **Queues & Backpressure** → **Consistency & Transactions** → **Observability** → **Failure Modes** → **Capacity Plan** → **Rollout/DR (RPO/RTO)** → **Risks & Alternatives**.

---

## Runbook Template (for each service)

- **Overview**: What service does; owners; links.
    
- **Dashboards/Alerts**: Links to Grafana/OpenSearch/CloudWatch.
    
- **SLOs**: e.g., p95 latency < 300ms; error rate < 0.5%.
    
- **Playbooks**: High CPU (scale/hot keys), DB connection spikes (pool/backoff), queue backlog (increase consumers), partial outage (canary rollback).
    
- **DR**: Backups, restore steps, RPO/RTO, failover command.
    

---

## First‑Week Checklist (Day‑by‑Day)

**Day 1**: Create repo + walking skeleton (FastAPI `/health` & `/query`), Dockerfile, basic tests, GitHub Actions CI, `ENGINEERING_LOG.md`.  
**Day 2**: Terraform VPC + EKS (or local Minikube), k8s Deployment/Service with readiness/liveness probes.  
**Day 3**: RDS Postgres + SQLAlchemy + Alembic migrations; create initial schema; connect app.  
**Day 4**: Redis for rate limiting & caching; JWT auth; OpenTelemetry tracing; Prometheus scrape config.  
**Day 5**: k6 load test; set initial SLOs; create first runbook; record Friday demo.  
**Weekend**: Add 10–15 Anki cards; write a 1‑page design doc for your RAG pipeline.

---

## Interview Prep Plan (Weeks 10–12 focus, but start light earlier)

- **System Design (3×/week):** 45‑min timed sessions; produce a one‑pager each time.
    
- **ML Theory:** bias/variance, metrics selection, leakage, monitoring/drift, retraining policies.
    
- **Behavioral:** STAR stories anchored in your demos (migration with zero data loss; adding SQS + idempotency; cost/latency minimization).
    
- **Demos:** 3 short videos (≤4 min each) embedded in README.
    

---

## Job Hunt Acceleration (Money & Momentum)

- **Branding:** LinkedIn headline + GitHub pin your 3 projects; write a 5‑line “What I built & why it matters.”
    
- **Networking (30m, 2×/week):** 5 targeted messages to hiring managers/ICs: 3‑line note + link to demo README.
    
- **Leverage your niche:** “GenAI Platform/Enablement” and “LLM App/Infra Engineer” roles.
    
- **Negotiation basics:** know your target range (base + RSU + bonus), use competing offers, ask for sign‑on to bridge gaps.
    

---

## Health, Energy, Family Integration

- **Sleep**: 7–8 hours; consistent bed/wake times.
    
- **Exercise**: 30–45 min every morning; weekend longer session ok.
    
- **Family Planning**: Share the 12‑week plan; reserve at least 1 evening fully off/week; protect weekends after your deep‑work blocks.
    

---

## Mindset & Metrics

- **Lead measures** (you control): 2×60‑min deep‑work sessions, 5 Anki cards/day, 1 demo/week.
    
- **Lag measures** (outcomes): portfolio completeness, interviews scheduled, offers.
    
- **Confidence Loop:** each Friday demo → one new story you can tell in interviews → self‑esteem climbs.
    

---

## Minimal Toolchain (keep it simple)

- **Code:** Python 3.11, FastAPI, SQLAlchemy, PyTorch, sentence‑transformers.
    
- **Infra:** AWS (EKS, RDS Postgres, S3, SQS, IAM), Terraform.
    
- **Ops:** GitHub Actions, OpenTelemetry, Prometheus/Grafana, k6, MLflow, Optuna.
    
- **Docs:** Markdown READMEs, ADRs, one‑pagers in `/docs`.
    

---

## Final Words

This plan turns you from “course‑taker” into **builder who ships**. Keep the rhythm (2×60‑min/day), ship weekly demos, lock knowledge with Anki, and make k8s/AWS/ML your **muscle memory**. That’s how you become the person who designs, delivers, and **gets paid accordingly**.

**Today → Create the repo, add the walking skeleton, and add your first 9 Anki cards.**

You’ve got this. Let’s go ship.


---
# 2
---

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

---

# 10× Cloud • ML • GenAI Curriculum & Project Map (Lead‑Along)

This is a **hands-on, end-to-end** study + project system to take you from solid Python dev → **Cloud/ML/GenAI engineer** with interview-proof artifacts. It assumes **2×60‑minute blocks/day** around a full-time job. It tells you **what to study** and **which project to build next**, day by day.

---

## North Star (why this makes you 10×)

* **Breadth that ships:** Cloud (AWS+k8s), ML (train/tune/ship), GenAI (RAG+evals+guardrails).
* **Depth where it counts:** reliability, cost/latency, observability, data quality.
* **Proof, not promises:** every week ends with a running demo; every concept becomes code.

---

## Tracks & Capstones

You’ll run 3 tracks in parallel; each ends in a capstone shipped to k8s:

1. **Cloud/Platform (EKS-first)** → *Capstone A: “Prod-grade RAG on EKS”*

   * Terraform VPC/EKS/RDS/S3/SQS/IAM
   * Helm/Kustomize, HPA, probes, secrets, RBAC
   * Prometheus/Grafana, OpenTelemetry, k6, runbooks

2. **ML/MLOps** → *Capstone B: “Tabular ML Pipeline with MLflow/Optuna + Batch Scoring”*

   * Data splits, metrics, training with PyTorch/Sklearn
   * MLflow tracking/registry, S3 artifacts, Optuna HPO
   * k8s CronJobs, drift checks, rollback policies

3. **GenAI Engineering** → *Capstone C: “Hybrid RAG (BM25+Vector) + Evals + Guardrails”*

   * Embedding choices, chunking, pgvector/OpenSearch
   * Evals (faithfulness/relevance), prompt A/B, caching
   * PII/toxicity guardrails, cost & latency dashboards

---

## Study Map (what to learn in each domain)

### Cloud (AWS+k8s)

* **Networking**: VPC, subnets (public/private), route tables, NAT vs IGW, SG/NACL.
* **Compute/Orchestration**: EKS (Deployments, Services, Ingress, HPA), node groups.
* **Storage**: RDS Postgres basics (connections, pooling, indexes), S3 patterns, backups/restore, RPO/RTO.
* **Messaging**: SQS (visibility timeout, DLQ), idempotent consumers.
* **Security**: IAM least‑privilege, Secrets Manager, Parameter Store.
* **Observability**: Prometheus metrics, Grafana dashboards, OpenTelemetry traces, CloudWatch alerts.
* **IaC**: Terraform modules, remote state, plan/apply workflow.

### ML/MLOps

* **Data discipline**: leakage prevention, splits, metrics selection.
* **Training**: PyTorch MLP for tabular, Sklearn baselines; early stopping.
* **Tuning**: Optuna searches, pruning; reproducibility seeds.
* **Tracking**: MLflow params/metrics/artifacts; model registry.
* **Serving/Batch**: versioned artifacts, k8s CronJobs, rollbacks.
* **Monitoring**: drift checks (input stats), calibration, alert thresholds.

### GenAI Engineering

* **Retrieval**: chunking strategies, embeddings, pgvector vs OpenSearch hybrid (BM25+vec).
* **Generation**: prompt templates, function calling, deterministic fallbacks.
* **Evals**: faithfulness, answer relevance; golden sets; offline vs shadow evals.
* **Guardrails**: PII redaction, toxicity filters, jailbreak mitigation.
* **Perf/Cost**: cache keys, TTL jitter, stampede control; token budgets.

### Systems Design (cross-cutting)

* Idempotency keys, retries/backoff, queues and backpressure, consistency models, pagination, caching strategies, rollouts (blue/green/canary), DR (RPO/RTO), capacity planning.

---

## Project Ladder (you always know the next build)

### Ladder 1 — *Resilient Backend Skeleton* (Week 1)

**Goal:** FastAPI on k8s with Postgres/Redis, tests, CI, basic tracing, k6 baseline.
**Milestones:** `/health`, `/query` stub → JWT → migrations → Redis rate limit → probes/HPA → Grafana → k6 report.

### Ladder 2 — *Tabular ML Pipeline* (Weeks 2–3)

**Goal:** Train/tune/persist a model; batch-score via CronJob; MLflow+Optuna.
**Milestones:** dataset → baseline → Optuna 50–100 trials → register best → CronJob writes to Postgres → drift check.

### Ladder 3 — *RAG v1 (pgvector)* (Weeks 3–4)

**Goal:** Ingest → embed → search → answer; citations; cache; first eval set.
**Milestones:** ingestion CLI → embeddings table (pgvector) → retrieval → answer route → Redis cache → 20‑question eval set.

### Ladder 4 — *Reliability & Scale* (Weeks 5–6)

**Goal:** Add SQS for async ingestion/re-embedding; idempotency; chaos tests; runbook.

### Ladder 5 — *Hybrid & Evals v2* (Weeks 7–8)

**Goal:** Hybrid search (+BM25/OpenSearch), prompt A/B, cost/latency dashboards, guardrails.

### Ladder 6 — *Polish & SDK* (Weeks 9–10)

**Goal:** Python client SDK (retries, metrics), better docs, ADRs, demo videos.

### Ladder 7 — *Interview Pack* (Weeks 11–12)

**Goal:** 3 system-design one-pagers, 3 live demos, resume/LinkedIn refresh, outreach.

---

## Daily Plan (2×60‑min) with Study Prompts

### Morning Block (Build)

* 10 min: skim today’s topic (from the day-by-day below) and add 1–2 Anki cards.
* 45–50 min: implement the day’s milestone task in code.
* 5 min: commit + quick note in `ENGINEERING_LOG.md`.

### Evening Block (Polish)

* 5 min: review metrics/tests from AM.
* 45–50 min: tests, docs, refactor, dashboards, or small load test.
* 5–10 min: add 3–4 Anki cards (total 5/day) + reflection.

---

## First 3 Weeks — Day-by-Day (exact tasks)

> After Week 3, repeat the same pattern with the Ladder milestones above.

### **Week 1 — Backend + k8s foundation**

**Mon**
AM: Repo + FastAPI `/health` + `/query` stub, pytest.
PM: Dockerfile + CI (tests+build).
**Study prompts:** "FastAPI pydantic validation", "pytest basics".

**Tue**
AM: Postgres + SQLAlchemy + Alembic; create schema.
PM: JWT auth + Redis rate limit middleware.
**Study prompts:** "B-tree index use", "rate limiting Redis token bucket".

**Wed**
AM: k8s Deployment/Service/Ingress; probes; HPA.
PM: OpenTelemetry traces; Prometheus scrape; Grafana dashboard.
**Study prompts:** "readiness vs liveness", "HPA CPU vs custom metrics".
**Scope Cut Ritual (15m)**: remove anything risking Friday.

**Thu**
AM: k6 baseline (20 RPS/5 min); set p95 target.
PM: Fix hot path; doc first runbook skeleton.
**Study prompts:** "latency percentiles", "connection pooling".

**Fri**
AM: Deploy to dev; smoke tests; tag `v0.1.0`.
PM: Record ≤4‑min demo; README update; log metrics.
**Study prompts:** "blue/green vs canary".

**Weekend (optional)**
Learning hour: Terraform VPC+EKS scaffolding or Minikube/Kind for local.

---

### **Week 2 — Tabular ML Pipeline**

**Mon**
AM: Dataset + baseline metric; MLflow tracking set up.
PM: Persist artifacts to S3; register model.
**Study prompts:** "leakage examples", "metric choice AUC/F1".

**Tue**
AM: Optuna HPO (≥50 trials); pruning.
PM: Load best run; integration test with API.
**Study prompts:** "Optuna sampler/pruner".

**Wed**
AM: k8s CronJob for batch scoring → Postgres table.
PM: Drift check job; alert threshold.
**Study prompts:** "population stability index (PSI)".
**Scope Cut**: if HPO overruns, cap trials and proceed.

**Thu**
AM: Dashboard: accuracy/latency/cost trend.
PM: Runbook section for jobs & rollbacks.
**Study prompts:** "rollback strategy".

**Fri**
AM: Demo: tuned model + batch scoring in k8s.
PM: README/diagram + video.

---

### **Week 3 — RAG v1**

**Mon**
AM: Ingestion CLI (PDF/Markdown → chunks).
PM: pgvector schema + embedding pipeline.
**Study prompts:** "chunking strategies".

**Tue**
AM: kNN search + citations; integrate with `/query`.
PM: Redis cache w/ TTL jitter + request coalescing.
**Study prompts:** "cache stampede".

**Wed**
AM: 20‑question eval set (golden answers).
PM: Eval harness: faithfulness/relevance scores persisted.
**Study prompts:** "RAG eval metrics".
**Scope Cut**: defer fancy rerankers if needed.

**Thu**
AM: Guardrails (PII/toxicity).
PM: Dashboards for hit rate, p95, token cost/request.
**Study prompts:** "PII detection patterns".

**Fri**
AM: Demo: RAG v1 with eval dashboard.
PM: README + video + ADR (“Why pgvector first”).

---

## Study “What to Search” (verbatim terms to paste into Google)

* **Cloud/k8s**: "Terraform EKS module example", "EKS Deployment yaml readiness probe", "HPA custom metrics", "RDS connection pooling pgbouncer".
* **Backend**: "FastAPI JWT middleware example", "SQLAlchemy Alembic migration tutorial", "Redis token bucket rate limit".
* **ML/MLOps**: "Optuna with MLflow tutorial", "PyTorch tabular classification example", "PSI drift sklearn".
* **GenAI**: "pgvector ivfflat create index example", "hybrid search BM25 vector OpenSearch", "RAG faithfulness evaluation".

---

## Templates (drop these into your repo)

* **One-Pager** per big change (`docs/designs/<topic>-<date>.md`) — sections: Context/Goals, Constraints, APIs/SLAs, Diagram, Data+Indexes, Scaling/Caching, Queues/Backpressure, Consistency, Observability, Failure Modes, Capacity/Cost, Rollout/DR, Risks/Alternatives, Decision.
* **Runbook** per service (`docs/runbooks/<service>.md`) — sections: Overview, SLOs, Dashboards, Alerts (meaning & actions), SOPs (CPU spikes, queue backlog, 5xx), Diagnostics commands, Rollbacks/Flags, Deploy/Release, DR/Backups, Security, Known Issues.

---

## Tracking & Accountability (don’t skip)

* **ENGINEERING_LOG.md** — morning & evening entries (focus, result, commit, metrics).
* **Scorecard (weekly)** — sessions completed (10), Anki cards (25), commits (≥10), demo shipped (Y/N), p95, 5xx, cost/1k, portfolio delta, outreach count.
* **Friday Reward** — attach a small family reward to the demo shipped.

---

## First Night (right now) — What to do

* Finish walking skeleton (API+tests+Docker+CI).
* Create `docs/designs/rag-skeleton-<date>.md` (1 page using template).
* Write `docs/runbooks/rag-api.md` (scaffold with sections).
* Add 5 Anki cards from today’s work (FastAPI routes, readiness vs liveness, B-tree index purpose, JWT vs sessions, cache stampede fixes).

---

## After Week 3 (how to continue)

Use the **Project Ladder** to pick the next two-week focus, repeat the day-by-day rhythm, and keep shipping Friday demos. By Week 12 you will have **three capstones**, interview stories, and a portfolio that commands compensation.

**Your Why:** “I ship weekly because my family’s future depends on it.” Pin that to the top of your README and never miss a Friday.
