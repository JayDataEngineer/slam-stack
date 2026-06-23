# Slam Stack — Makefile
# Convenience targets for common operations.
# ./bootstrap.sh is the canonical "from scratch" entry point.
# Set FLAVOR=minimal|core|og|matrix|commet|rust to select flavor (default: og).

SHELL := /bin/bash
KUBECONFIG := $(HOME)/.kube/slam-stack-config
FLAVOR ?= og
TOFU_DIR := tofu
TOFU_IMAGE := ghcr.io/opentofu/opentofu:1.9.0
TOFU := docker run --rm -i \
  -v $(PWD):/workspace \
  -v $(HOME)/.kube:/root/.kube \
  -w /workspace \
  $(TOFU_IMAGE)

# OpenTofu variables (set via env or terraform.tfvars)
NODE_IP ?=
DOMAIN ?= slam.lab
INSTALL_DISK ?= /dev/sda
GIT_REPO_URL ?= $(shell git remote get-url origin 2>/dev/null || echo "https://github.com/your-org/slam-stack.git")
GIT_BRANCH ?= master
CREATE_VMS ?=

.PHONY: all bootstrap bootstrap-minimal bootstrap-og bootstrap-matrix bootstrap-rust setup \
        deploy deploy-minimal deploy-og deploy-matrix deploy-core deploy-rust deploy-commet \
        verify e2e e2e-flux e2e-matrix web web-push sign clean cluster destroy tofu-* \
        test test-static test-policy test-unit test-flux test-live test-browser test-kind help

all: help

## bootstrap — Full repro from scratch (FLAVOR=og by default)
bootstrap:
	FLAVOR=$(FLAVOR) ./bootstrap.sh

## bootstrap-minimal — Full repro with minimal flavor (security plane only, ~2 GiB)
bootstrap-minimal:
	FLAVOR=minimal ./bootstrap.sh

## bootstrap-og — Full repro with OG flavor (Stalwart + SimpleX)
bootstrap-og:
	FLAVOR=og ./bootstrap.sh

## bootstrap-matrix — Full repro with Matrix flavor (Tuwunel + Cinny + LiveKit)
bootstrap-matrix:
	FLAVOR=matrix ./bootstrap.sh

## bootstrap-rust — Full repro with rust flavor (Stalwart + Tuwunel, both Rust)
bootstrap-rust:
	FLAVOR=rust ./bootstrap.sh

## setup — Create dev cluster + Cilium only
setup:
	./dev/setup.sh

## deploy — Deploy all stack components (current FLAVOR)
deploy:
	FLAVOR=$(FLAVOR) KUBECONFIG=$(KUBECONFIG) ./deploy.sh

## deploy-minimal — Deploy minimal flavor (Cilium + Kyverno + cert-manager + Vault + Kanidm + Headscale)
deploy-minimal:
	FLAVOR=minimal KUBECONFIG=$(KUBECONFIG) ./deploy.sh

## deploy-og — Deploy OG flavor (Stalwart + SimpleX)
deploy-og:
	FLAVOR=og KUBECONFIG=$(KUBECONFIG) ./deploy.sh

## deploy-matrix — Deploy Matrix flavor (Tuwunel + Cinny + LiveKit)
deploy-matrix:
	FLAVOR=matrix KUBECONFIG=$(KUBECONFIG) ./deploy.sh

## deploy-rust — Deploy Rust flavor (Stalwart + Tuwunel — both Rust servers)
deploy-rust:
	FLAVOR=rust KUBECONFIG=$(KUBECONFIG) ./deploy.sh

## deploy-commet — Deploy Commet flavor (Tuwunel + Commet Flutter client)
deploy-commet:
	FLAVOR=commet KUBECONFIG=$(KUBECONFIG) ./deploy.sh

## deploy-core — Deploy only core (no flavor apps)
deploy-core:
	FLAVOR=core KUBECONFIG=$(KUBECONFIG) ./deploy.sh

## verify — Run security posture verification
verify:
	FLAVOR=$(FLAVOR) KUBECONFIG=$(KUBECONFIG) ./verify.sh

## e2e — Run flavor-specific e2e tests (if it exists)
e2e:
	@if [ -f "./scripts/e2e-$(FLAVOR).sh" ]; then \
		FLAVOR=$(FLAVOR) KUBECONFIG=$(KUBECONFIG) ./scripts/e2e-$(FLAVOR).sh; \
	else \
		echo "No e2e-$(FLAVOR).sh — running e2e-flux.sh (cluster-offline pipeline check)"; \
		FLAVOR=$(FLAVOR) ./scripts/e2e-flux.sh; \
	fi

## e2e-flux — Flux pipeline build/lint/policy checks (no cluster needed)
e2e-flux:
	FLAVOR=$(FLAVOR) ./scripts/e2e-flux.sh

## e2e-matrix — Matrix flavor end-to-end live cluster test
e2e-matrix:
	FLAVOR=matrix KUBECONFIG=$(KUBECONFIG) ./scripts/e2e-matrix.sh

## web — Build web dashboard (requires Rust)
web:
	./web/build.sh

## web-push — Build web dashboard and push to local registry
web-push:
	./web/build.sh --push

## sign — Sign all scripts with Cosign
sign:
	@for f in $$(find . -name '*.sh' -type f); do \
		echo "Signing $$f..."; \
		COSIGN_PASSWORD="" cosign sign-blob --key components/cosign/cosign.key \
			--bundle "$${f}.bundle" "$$f" 2>/dev/null; \
	done
	@echo "All scripts signed"

# Either NODE_IP (existing Talos node) or CREATE_VMS=true (libvirt module) must be set.
tofu_vars = $(if $(CREATE_VMS), \
  -var="create_vms=true" -var="domain=$(DOMAIN)" \
  -var="flavor=$(FLAVOR)" -var="install_disk=$(INSTALL_DISK)" \
  -var="git_repo_url=$(GIT_REPO_URL)" -var="git_branch=$(GIT_BRANCH)", \
  $(if $(NODE_IP), \
    -var="node_ip=$(NODE_IP)" -var="domain=$(DOMAIN)" \
    -var="flavor=$(FLAVOR)" -var="install_disk=$(INSTALL_DISK)" \
    -var="git_repo_url=$(GIT_REPO_URL)" -var="git_branch=$(GIT_BRANCH)", \
    $(error Set NODE_IP (existing Talos node) or CREATE_VMS=true (libvirt provisioner): \
      export NODE_IP=192.168.1.100)))

## tofu-init — Initialize OpenTofu working directory (via container)
tofu-init:
	@docker info >/dev/null 2>&1 || { echo "ERROR: Docker required for tofu targets"; exit 1; }
	$(TOFU) -chdir=$(TOFU_DIR) init

## tofu-plan — Preview the Talos cluster + Flux bootstrap plan
tofu-plan:
	@docker info >/dev/null 2>&1 || { echo "ERROR: Docker required"; exit 1; }
	$(TOFU) -chdir=$(TOFU_DIR) plan $(tofu_vars)

## cluster — Create Talos cluster + Flux bootstrap (tofu in container)
cluster: tofu-init
	$(TOFU) -chdir=$(TOFU_DIR) apply $(tofu_vars)
	@echo "Cluster created. Kubeconfig at ~/.kube/slam-stack-config"

## tofu-destroy — Tear down the Talos cluster via OpenTofu
tofu-destroy:
	@docker info >/dev/null 2>&1 || { echo "ERROR: Docker required"; exit 1; }
	$(TOFU) -chdir=$(TOFU_DIR) destroy $(tofu_vars)

## clean — Destroy dev cluster
clean:
	sudo talosctl cluster destroy --name slam-stack-dev 2>/dev/null || true
	rm -f $(KUBECONFIG)

## destroy — Destroy cluster and remove all tooling
destroy: clean
	sudo rm -f /usr/local/bin/talosctl
	sudo rm -f /usr/local/bin/kubectl
	sudo rm -f /usr/local/bin/helm
	sudo rm -f /usr/local/bin/cosign

# ──────────────────────────────────────────────────────────────────────────
# Test suite — delegates to tests/Makefile
# ──────────────────────────────────────────────────────────────────────────

## test — Run all Tier 1 tests (static + policy + flux + unit, no cluster)
test:
	$(MAKE) -C tests test

## test-static — shellcheck + yamllint + kubeconform (no cluster)
test-static:
	$(MAKE) -C tests test-static

## test-policy — Kyverno admission policy tests (no cluster)
test-policy:
	$(MAKE) -C tests test-policy

## test-flux — Flux pipeline build/lint check (no cluster)
test-flux:
	$(MAKE) -C tests test-flux FLAVOR=$(FLAVOR)

## test-unit — Rust unit tests for sample-rust-app and web dashboard
test-unit:
	$(MAKE) -C tests test-unit

## test-live — curl-based live endpoint checks (REQUIRES cluster)
test-live:
	$(MAKE) -C tests test-live

## test-browser — Playwright UI tests via Docker (REQUIRES cluster)
test-browser:
	$(MAKE) -C tests test-browser

## test-kind — Spin up kind cluster, deploy, run smoke tests
test-kind:
	$(MAKE) -C tests test-kind

## help — Show this message
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## //' | column -t -s '—'
