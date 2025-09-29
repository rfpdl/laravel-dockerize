SHELL := /bin/bash

.PHONY: help up down build logs ps prune e2e

help:
	@echo "Targets:"
	@echo "  up        - docker compose up -d (local preset)"
	@echo "  down      - docker compose down -v (local preset)"
	@echo "  build     - docker compose build (local preset)"
	@echo "  logs      - docker compose logs -f (local preset)"
	@echo "  ps        - docker compose ps (local preset)"
	@echo "  prune     - docker system prune -f"
	@echo "  e2e       - run end-to-end test harness"

up:
	docker compose -f docker-compose.local.yml up -d

build:
	docker compose -f docker-compose.local.yml build

logs:
	docker compose -f docker-compose.local.yml logs -f

ps:
	docker compose -f docker-compose.local.yml ps

down:
	docker compose -f docker-compose.local.yml down -v

prune:
	docker system prune -f

e2e:
	chmod +x tests/run-e2e.sh && tests/run-e2e.sh
