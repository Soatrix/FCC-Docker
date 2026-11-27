# FCC Docker repository helpers.
# Override variables on the command line, e.g.:
#   make build FCC_VERSION=6.19.57 IMAGE=ghcr.io/soatrix/free-claude-code:6.19.57
#   make publish FCC_VERSION=6.19.57 IMAGE=ghcr.io/soatrix/free-claude-code:6.19.57

IMAGE_ORG ?= soatrix
FCC_VERSION ?= 6.19.57
IMAGE ?= ghcr.io/$(IMAGE_ORG)/free-claude-code:$(FCC_VERSION)
IMAGE_TAG ?= $(FCC_VERSION)
FCC_VERSION_EXPECTED ?= $(FCC_VERSION)
DOCKERFILE ?= docker/fcc/Dockerfile
BUILD_CONTEXT ?= docker/fcc
VCS_REF ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)

.DEFAULT_GOAL := help

.PHONY: help build smoke publish deploy rollback check-upstream fmt lint

help: ## Show available targets.
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-16s %s\n", $$1, $$2}'

build: ## Build a single-arch FCC image locally.
	docker build \
		--file $(DOCKERFILE) \
		--build-arg FCC_VERSION=$(FCC_VERSION) \
		--build-arg VCS_REF=$(VCS_REF) \
		--build-arg SOURCE_URL=https://github.com/$(IMAGE_ORG)/FCC-Docker \
		--tag $(IMAGE) \
		$(BUILD_CONTEXT)

smoke: ## Smoke-test $(IMAGE); set FCC_VERSION_EXPECTED to override the version assertion.
	FCC_VERSION_EXPECTED=$(FCC_VERSION_EXPECTED) bash scripts/smoke-test.sh $(IMAGE)

publish: build smoke ## Build, smoke-test, and push a multi-arch image to GHCR.
	docker buildx build \
		--platform linux/amd64,linux/arm64 \
		--file $(DOCKERFILE) \
		--build-arg FCC_VERSION=$(FCC_VERSION) \
		--build-arg VCS_REF=$(VCS_REF) \
		--build-arg SOURCE_URL=https://github.com/$(IMAGE_ORG)/FCC-Docker \
		--tag $(IMAGE) \
		--push \
		$(BUILD_CONTEXT)

deploy: ## Trigger EasyPanel deployment for IMAGE_TAG.
	IMAGE_TAG=$(IMAGE_TAG) bash scripts/deploy.sh $(IMAGE_TAG)

rollback: ## Roll back to an immutable IMAGE_TAG (version or sha tag).
	IMAGE_TAG=$(IMAGE_TAG) bash scripts/rollback.sh $(IMAGE_TAG)

check-upstream: ## Check upstream FCC release and update config/fcc-version.json.
	bash scripts/check-upstream.sh

fmt: ## Format shell scripts with shfmt if installed.
	@if command -v shfmt >/dev/null 2>&1; then \
		shfmt -w -i 2 -ci scripts/*.sh; \
	else \
		echo "shfmt not found; install shfmt to format scripts"; \
	fi

lint: ## Lint shell scripts with shellcheck if installed.
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck scripts/*.sh; \
	else \
		echo "shellcheck not found; install shellcheck to lint scripts"; \
	fi
