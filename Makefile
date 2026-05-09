# Slam Stack — Makefile
# Convenience targets for common operations.
# ./bootstrap.sh is the canonical "from scratch" entry point.

SHELL := /bin/bash
KUBECONFIG := $(HOME)/.kube/slam-stack-config

.PHONY: all bootstrap setup deploy verify web-sign clean destroy help

all: help

## bootstrap — Full repro from scratch (Ubuntu 26.04 host)
bootstrap:
	./bootstrap.sh

## setup — Create dev cluster + Cilium only
setup:
	./dev/setup.sh

## deploy — Deploy all stack components
deploy:
	KUBECONFIG=$(KUBECONFIG) ./deploy.sh

## verify — Run security posture verification
verify:
	KUBECONFIG=$(KUBECONFIG) ./verify.sh

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
