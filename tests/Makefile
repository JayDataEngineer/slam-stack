# =============================================================================
# Slam Stack — Test Orchestration
# =============================================================================
#
# Three tiers, runnable independently or together:
#
#   make test-static    # Tier 1: shellcheck, yamllint, kubeconform (no cluster)
#   make test-policy    # Tier 1: kyverno admission policy tests (no cluster)
#   make test-unit      # Tier 1: cargo tests for Rust components (no cluster)
#   make test-flux      # Tier 1: Flux pipeline build/lint (no cluster)
#   make test-live      # Tier 2: curl-based endpoint checks (REQUIRES cluster)
#   make test-browser   # Tier 3: Playwright UI tests via Docker (REQUIRES cluster)
#   make test           # All Tier 1 tests (safe to run in CI, no cluster)
#
# Environment:
#   FLAVOR      - which flavor to test (default: og)
#   KUBECONFIG  - cluster kubeconfig (Tier 2/3)
#   BASE_URL    - dashboard base URL (Tier 3, default: https://slamstack.internal)
#
# Tooling is containerized — no host installs needed beyond docker + bash + make.

SHELL := /bin/bash
TESTS_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(TESTS_DIR)/..)
FLAVOR ?= og
KUBECONFIG ?= $(HOME)/.kube/slam-stack-config
BASE_URL ?= https://slamstack.internal

# Pinned tool versions (deterministic CI)
KIND_IMAGE ?= kindest/node:v1.32.0
KYVERNO_CLI_IMAGE := ghcr.io/kyverno/kyverno-cli:v1.13.4
KUBECONFORM_IMAGE := ghcr.io/yannh/kubeconform:latest
SHELLCHECK_IMAGE := koalaman/shellcheck:stable
YAMLLINT_IMAGE := pipelinecomponents/yamllint:latest
PLAYWRIGHT_IMAGE := mcr.microsoft.com/playwright:v1.52.0-noble

export REPO_ROOT FLAVOR KUBECONFIG BASE_URL
export KYVERNO_CLI_IMAGE KUBECONFORM_IMAGE SHELLCHECK_IMAGE YAMLLINT_IMAGE PLAYWRIGHT_IMAGE

.DEFAULT_GOAL := help
.PHONY: help test test-static test-policy test-unit test-flux test-live test-browser test-kind

all: test

## test — Run all Tier 1 tests (no cluster required)
test: test-static test-policy test-flux test-unit
	@echo ""
	@echo "=== All Tier 1 tests passed ==="
	@echo "Run 'make test-live' for live cluster endpoint checks (requires cluster)"
	@echo "Run 'make test-browser' for Playwright UI tests (requires cluster + Docker)"

## test-static — shellcheck + yamllint + kubeconform (no cluster)
test-static:
	@echo "=== Tier 1: Static analysis ==="
	$(TESTS_DIR)/static/run-all.sh

## test-policy — Kyverno admission control tests against mock resources
test-policy:
	@echo "=== Tier 1: Kyverno policy tests ==="
	$(TESTS_DIR)/policy/run-all.sh

## test-flux — Flux pipeline build + dependency + signature checks (offline)
test-flux:
	@echo "=== Tier 1: Flux pipeline e2e ==="
	cd $(REPO_ROOT) && FLAVOR=$(FLAVOR) ./scripts/e2e-flux.sh

## test-unit — cargo test for Rust components (requires cargo)
test-unit:
	@echo "=== Tier 1: Rust unit tests ==="
	$(TESTS_DIR)/unit/run-all.sh

## test-live — curl-based endpoint checks against a deployed cluster
test-live:
	@echo "=== Tier 2: Live cluster endpoint checks ==="
	$(TESTS_DIR)/e2e/endpoint-check.sh

## test-browser — Playwright UI tests via Docker (requires cluster)
test-browser:
	@echo "=== Tier 3: Playwright browser tests ==="
	$(TESTS_DIR)/browser/run-docker.sh

## test-kind — Spin up a kind cluster, deploy, run all tests (CI smoke)
test-kind:
	@echo "=== CI smoke: kind cluster + deploy + test ==="
	$(TESTS_DIR)/ci/kind-smoke.sh

## help — Show this message
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## //' | column -t -s '—'
