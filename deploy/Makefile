# Convenience targets for the Kubeport eval stack.  All real work lives in
# docker-compose.yml; this just shortens the commands graders type.

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: build
build: ## Build the kubeport image (one-time, ~5–10 min).
	docker compose build kubeport

.PHONY: up
up: ## Start the stack in the background.
	docker compose up -d

.PHONY: down
down: ## Stop the stack but keep volumes.
	docker compose down

.PHONY: nuke
nuke: ## Stop the stack AND wipe all volumes (db, sites, k3s state).
	docker compose down -v

.PHONY: logs
logs: ## Tail logs for every service.
	docker compose logs -f

.PHONY: logs-bench
logs-bench: ## Tail only the bench (web / worker / scheduler) logs.
	docker compose logs -f kubeport

.PHONY: logs-k3s
logs-k3s: ## Tail only the k3s logs.
	docker compose logs -f k3s

.PHONY: shell
shell: ## Open a bash shell inside the running bench container.
	docker compose exec kubeport bash

.PHONY: kubeconfig
kubeconfig: ## Print the k3s kubeconfig (with host-side server URL) so you can `kubectl` from the host.
	@docker compose exec k3s sh -c 'cat /shared/k3s/kubeconfig.yaml | sed "s|server: https://127.0.0.1:6443|server: https://localhost:$${K3S_HOST_PORT:-6443}|"'

.PHONY: status
status: ## Show service health.
	docker compose ps
