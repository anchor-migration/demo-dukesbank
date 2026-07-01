.PHONY: help up down build e2e e2e-jpa stubborn shell

help:
	@echo "Duke's Bank demo — Docker-first targets"
	@echo "  make up        Start MySQL"
	@echo "  make e2e       Schema + code + crosswalk"
	@echo "  make e2e-jpa   CMP->JPA + per-entity parity"
	@echo "  make stubborn  anchor-stubborn LLM context (Step 7)"
	@echo "  make shell     Interactive runner container"

up:
	docker compose up -d mysql

down:
	docker compose down

build:
	docker compose build runner

e2e: build
	./scripts/run-e2e.sh

e2e-jpa: build
	./scripts/run-e2e-jpa-parity.sh

stubborn:
	./scripts/run-stubborn-context.sh

shell: build
	docker compose run --rm runner
