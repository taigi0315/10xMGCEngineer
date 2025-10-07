# Engineering Log

## [2025-10-6] - Morning
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

