# Engineering Log

## [2025-10-6-Morning]
- Goal: Create repo + walking skeleton and solidify local/CI workflows
- Decisions:
  - Stack: FastAPI, Uvicorn, Pytest
  - Endpoints: GET /health, POST/GET /query
- Changes:
  - Implemented endpoints in apps/api/main.py
  - Added apps/api/tests/test_app.py with 3 tests
  - Added apps/api/Dockerfile and apps/api/.dockerignore
  - Added CI workflow at .github/workflows/ci.yml (install, tests, docker build)
  - Root Makefile: introduced .venv usage and namespaced targets (`api-*`)
  - Simplified aliases: `install/test/run/docker*` now delegate to `api-*`
  - Fixed pytest discovery to run via `apps/api/tests`
  - Requirements: added `httpx==0.27.2` for TestClient
  - Repo hygiene: moved ENGINEERING_LOG.md to root, removed apps/pytest.ini
- Results:
  - `make api-install && make api-test` passes locally
  - Consistent local/CI behaviors via namespaced targets
- Next:
  - Add validation & schemas
  - Extend /query with real logic
  - Add lint/format (ruff/black) with Make targets and CI steps
  - Containerize test run (optional) and add GHCR/Docker Hub push steps

## [2025-10-6-Evening] - Day 1 Complete (Walking Skeleton)
- Goal: FastAPI skeleton + Docker + CI + tests working end-to-end
- Morning Block (60min):
  - Created FastAPI app with /health and /query endpoints
  - Wrote 3 tests with TestClient (health, POST query, GET query)
  - Set up Dockerfile with Python 3.11-slim
  - Added pytest.ini and root Makefile with venv + namespaced targets
- Evening Block (60min):
  - Fixed Git push issues (refs corruption → fresh clone workaround)
  - Cleaned up Makefile duplicates → api-* namespace only
  - Added httpx dependency for TestClient
  - Successfully built Docker image and tested all endpoints
- Results:
  - ✅ Docker image: `10xmgcengineer-api:dev` built successfully
  - ✅ All endpoints tested: /health, POST /query, GET /query
  - ✅ Tests pass: 3/3 (health, query_post, query_get)
  - ✅ CI workflow: .github/workflows/ci.yml ready
  - ✅ Git: upstream tracking fixed, code pushed to GitHub
- Blockers: None
- Commits: 4 (walking skeleton, requirements, tests, Makefile cleanup)
- Next (Day 2 - Tue):
  - AM: Postgres + SQLAlchemy + Alembic migrations
  - PM: JWT auth + Redis rate limiting
  - Study: "B-tree index", "rate limiting Redis token bucket"

