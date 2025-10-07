# 프로젝트 루트에서 사용
# 사용 예) make install / make test / make run / make docker

APP_DIR := apps/api
REQ     := $(APP_DIR)/requirements.txt
IMAGE   := 10xmgcengineer-api:dev

.PHONY: help install test run run-api docker-build docker-run docker

help:
	@echo "Available targets:"
	@echo "  make install       - pip install -r apps/api/requirements.txt"
	@echo "  make test          - pytest -q (루트에서 실행)"
	@echo "  make run           - uvicorn apps.api.main:app --reload (루트 기준)"
	@echo "  make run-api       - cd apps/api && uvicorn main:app --reload"
	@echo "  make docker-build  - cd apps/api && docker build -t $(IMAGE) ."
	@echo "  make docker-run    - docker run --rm -p 8000:8000 $(IMAGE)"
	@echo "  make docker        - build 후 바로 run"

install:
	pip install -r $(REQ)

test:
	pytest -q

run:
	uvicorn apps.api.main:app --reload

run-api:
	cd $(APP_DIR) && uvicorn main:app --reload

docker-build:
	cd $(APP_DIR) && docker build -t $(IMAGE) .

docker-run:
	docker run --rm -p 8000:8000 $(IMAGE)

docker: docker-build docker-run