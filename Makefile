# Makefile - Check, plan and apply the Terraform stacks.
# Usage: make help
#
# The same targets run locally and in CI. Terraform uses whatever AWS
# credentials are in the environment, such as AWS_PROFILE=neon1 locally.

# Every folder with a versions.tf is a stack
STACKS := $(patsubst %/versions.tf,%,$(wildcard */versions.tf))
STACK  ?=
PLAN   := tfplan

# Pinned images stand in for tools that aren't installed
TFLINT_IMAGE   := ghcr.io/terraform-linters/tflint:v0.65.0
TRIVY_IMAGE    := ghcr.io/aquasecurity/trivy:0.76.1
GITLEAKS_IMAGE := ghcr.io/gitleaks/gitleaks:v8.30.1
DOCKER_RUN     := docker run --rm -u "$$(id -u):$$(id -g)" -v "$(CURDIR):/src" -w /src

.DEFAULT_GOAL := help
.PHONY: help check fmt fmt-check validate lint sec secrets plan apply stack


##@ Checks

check: fmt-check validate lint sec secrets ## Run every static check

fmt: ## Format all Terraform files
	terraform fmt -recursive

fmt-check: ## Fail if any Terraform file needs formatting
	terraform fmt -check -recursive -diff

validate: ## Validate each stack without touching remote state
	@for s in $(STACKS); do \
		echo "validate $$s"; \
		terraform -chdir=$$s init -backend=false -input=false >/dev/null || exit 1; \
		terraform -chdir=$$s validate -no-color || exit 1; \
	done

# CI always has Docker, so only a local run without either tool skips
lint: ## Lint with tflint
	@if command -v tflint >/dev/null 2>&1; then \
		tflint --recursive --config "$(CURDIR)/.tflint.hcl"; \
	elif docker info >/dev/null 2>&1; then \
		$(DOCKER_RUN) $(TFLINT_IMAGE) --recursive --config /src/.tflint.hcl; \
	elif [ -n "$$CI" ]; then \
		echo "lint: tflint and Docker are both missing"; exit 1; \
	else \
		echo "lint: skipped, install tflint or start Docker"; \
	fi

sec: ## Scan for misconfigurations with trivy (accepted findings are in .trivyignore)
	@if command -v trivy >/dev/null 2>&1; then \
		trivy config --severity HIGH,CRITICAL --exit-code 1 --quiet .; \
	else \
		$(DOCKER_RUN) -e TRIVY_CACHE_DIR=/tmp/trivy $(TRIVY_IMAGE) \
			config --severity HIGH,CRITICAL --exit-code 1 --quiet .; \
	fi

secrets: ## Scan the git history for secrets with gitleaks
	@if command -v gitleaks >/dev/null 2>&1; then \
		gitleaks git --redact --no-banner .; \
	else \
		$(DOCKER_RUN) $(GITLEAKS_IMAGE) git --redact --no-banner /src; \
	fi


##@ Stacks

plan: stack ## Save a plan for one stack: make plan STACK=site
	terraform -chdir=$(STACK) init -input=false
	terraform -chdir=$(STACK) plan -input=false -out=$(PLAN)

# Applies exactly what was planned, then drops the plan so it can't be reused
apply: stack ## Apply the saved plan for one stack: make apply STACK=site
	@test -f $(STACK)/$(PLAN) || { echo "apply: run make plan STACK=$(STACK) first"; exit 1; }
	@terraform -chdir=$(STACK) apply -input=false $(PLAN); \
	status=$$?; \
	rm -f $(STACK)/$(PLAN); \
	exit $$status

stack:
	@test -n "$(STACK)" && test -f "$(STACK)/versions.tf" || { \
		echo "Set STACK to one of: $(STACKS)"; exit 1; }


##@ Help

help: ## Show targets
	@awk 'BEGIN {FS = ":.*## "} \
		/^##@/ {printf "\n%s\n", substr($$0, 5)} \
		/^[a-z-]+:.*## / {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Stacks: $(STACKS)"
