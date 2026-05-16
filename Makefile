# Slam Stack — Makefile
# Convenience targets for common operations.
# ./bootstrap.sh is the canonical "from scratch" entry point.
# Set FLAVOR=og|matrix|core to select flavor (default: og).

SHELL := /bin/bash
KUBECONFIG := $(HOME)/.kube/slam-stack-config
FLAVOR ?= og

.PHONY: all bootstrap bootstrap-og bootstrap-matrix setup deploy deploy-og deploy-matrix deploy-core verify web web-push sign clean destroy help

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
