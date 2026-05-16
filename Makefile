# Slam Stack — Makefile
# Convenience targets for common operations.
# ./bootstrap.sh is the canonical "from scratch" entry point.
# Set FLAVOR=og|matrix|core to select flavor (default: og).

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

.PHONY: all bootstrap bootstrap-og bootstrap-matrix setup deploy deploy-og deploy-matrix deploy-core verify web web-push sign clean cluster destroy tofu-* help

all: help

## bootstrap — Full repro from scratch (Ubuntu 26.04 host, FLAVOR=og)
bootstrap:
	FLAVOR=$(FLAVOR) ./bootstrap.sh

## bootstrap-og — Full repro with OG flavor (Stalwart + SimpleX)
bootstrap-og:
	FLAVOR=og ./bootstrap.sh

## bootstrap-matrix — Full repro with Matrix flavor (Continuwuity + Cinny + LiveKit)
bootstrap-matrix:
	FLAVOR=matrix ./bootstrap.sh

## setup — Create dev cluster + Cilium only
setup:
	./dev/setup.sh

## deploy — Deploy all stack components (FLAVOR=og)
deploy:
	FLAVOR=$(FLAVOR) KUBECONFIG=$(KUBECONFIG) ./deploy.sh

## deploy-og — Deploy OG flavor (Stalwart + SimpleX)
deploy-og:
	FLAVOR=og KUBECONFIG=$(KUBECONFIG) ./deploy.sh

## deploy-matrix — Deploy Matrix flavor (Continuwuity + Cinny + LiveKit)
deploy-matrix:
	FLAVOR=matrix KUBECONFIG=$(KUBECONFIG) ./deploy.sh

## deploy-core — Deploy only core (no flavor apps)
deploy-core:
	FLAVOR=core KUBECONFIG=$(KUBECONFIG) ./deploy.sh

## verify — Run security posture verification
verify:
	FLAVOR=$(FLAVOR) KUBECONFIG=$(KUBECONFIG) ./verify.sh

## e2e-matrix — Run Matrix flavor end-to-end tests
e2e-matrix:
	FLAVOR=matrix KUBECONFIG=$(KUBECONFIG) ./scripts/e2e-matrix.sh

## e2e — Run flavor-specific e2e tests
e2e:
	FLAVOR=$(FLAVOR) KUBECONFIG=$(KUBECONFIG) ./scripts/e2e-$(FLAVOR).sh

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

tofu_vars = $(if $(NODE_IP), \
  -var="node_ip=$(NODE_IP)" -var="domain=$(DOMAIN)" \
  -var="flavor=$(FLAVOR)" -var="install_disk=$(INSTALL_DISK)" \
  -var="git_repo_url=$(GIT_REPO_URL)" -var="git_branch=$(GIT_BRANCH)", \
  $(error Set NODE_IP: export NODE_IP=192.168.1.100))

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

## help — Show this message
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## //' | column -t -s '—'
