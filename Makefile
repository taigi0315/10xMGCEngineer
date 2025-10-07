# 루트 Makefile: apps/api 작업을 위임

APP_DIR := apps/api
REQ     := $(APP_DIR)/requirements.txt
IMAGE   := 10xmgcengineer-api:dev

# Virtualenv settings
VENV    := .venv
PYTHON  := python3
PIP     := $(VENV)/bin/pip
PYTEST  := $(VENV)/bin/pytest
UVICORN := $(VENV)/bin/uvicorn

.PHONY: help venv install test run run-api docker-build docker-run docker clean-venv \
        api-install api-test api-run api-docker-build api-docker-run api-docker

help:
	@echo "Available targets:"
	@echo "  make venv          - $(PYTHON) -m venv $(VENV)"
	@echo "  make install       - $(PIP) install -r apps/api/requirements.txt"
	@echo "  make test          - $(PYTEST) -q (루트에서 실행)"
	@echo "  make run           - $(UVICORN) apps.api.main:app --reload (루트 기준)"
	@echo "  make run-api       - cd apps/api && uvicorn main:app --reload"
	@echo "  make docker-build  - cd apps/api && docker build -t $(IMAGE) ."
	@echo "  make docker-run    - docker run --rm -p 8000:8000 $(IMAGE)"
	@echo "  make docker        - build 후 바로 run"
	@echo "  --- Namespaced targets ---"
	@echo "  make api-install   - install for apps/api"
	@echo "  make api-test      - test for apps/api"
	@echo "  make api-run       - run apps/api"
	@echo "  make api-docker-build - docker build apps/api"
	@echo "  make api-docker-run   - docker run apps/api image"
	@echo "  make api-docker       - build+run apps/api image"
	@echo "  make clean-venv    - remove $(VENV)"

venv:
	$(PYTHON) -m venv $(VENV)

install: api-install

test: api-test

run: api-run

run-api: api-run

docker-build: api-docker-build

docker-run: api-docker-run

docker: api-docker

# Namespaced API targets (aliases with explicit namespace)
api-install: venv
	$(PIP) install --upgrade pip
	$(PIP) install -r $(REQ)

api-test: 
	$(PYTEST) -q apps/api/tests

api-run:
	$(UVICORN) apps.api.main:app --reload

api-docker-build:
	cd $(APP_DIR) && docker build -t $(IMAGE) .

api-docker-run:
	docker run --rm -p 8000:8000 $(IMAGE)

api-docker: api-docker-build api-docker-run

clean-venv:
	rm -rf $(VENV)

