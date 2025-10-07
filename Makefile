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

.PHONY: help venv clean-venv \
        api-install api-test api-run api-docker-build api-docker-run api-docker

help:
	@echo "=== 10xMGCEngineer Makefile ==="
	@echo ""
	@echo "API Service:"
	@echo "  make api-install       - Create venv & install dependencies"
	@echo "  make api-test          - Run tests"
	@echo "  make api-run           - Run FastAPI dev server"
	@echo "  make api-docker-build  - Build Docker image"
	@echo "  make api-docker-run    - Run Docker container"
	@echo "  make api-docker        - Build & run Docker"
	@echo ""
	@echo "Utility:"
	@echo "  make venv              - Create virtual environment only"
	@echo "  make clean-venv        - Remove .venv"

venv:
	$(PYTHON) -m venv $(VENV)

# API targets
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

