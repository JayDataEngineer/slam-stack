# Slam Stack Test Suite

Three-tier testing architecture that ensures zero regressions when shipping.

## Quick Start

```bash
# Run all offline tests (no cluster needed)
make -C tests test

# Or from the repo root:
make test
```

## Architecture

### Tier 1: Offline (no cluster required)

| Target | What it checks | Tools |
|--------|---------------|-------|
| `test-static` | shellcheck on all `.sh`, yamllint on all YAML, kubeconform on all k8s manifests | Docker: `koalaman/shellcheck`, `pipelinecomponents/yamllint`, `ghcr.io/yannh/kubeconform` |
| `test-policy` | Kyverno admission policies reject non-compliant pods and accept compliant ones | Docker: `ghcr.io/kyverno/kyverno-cli:v1.13.4` |
| `test-flux` | Flux pipeline: kustomize builds, dependency chains, HelmRelease references, secret hygiene | `scripts/e2e-flux.sh` |
| `test-unit` | Rust unit tests for sample-rust-app and web dashboard | `cargo test` |

**All Tier 1 tests run in CI** (`.github/workflows/test.yml`) on every push/PR.

### Tier 2: Live Cluster (requires deployed slam-stack)

```bash
KUBECONFIG=~/.kube/slam-stack-config make test-live
```

Uses `kubectl port-forward` + `curl` to verify every in-cluster service responds.
Checks: API health, node readiness, pod status, endpoint responses per flavor,
NetworkPolicy enforcement, Kyverno policy activation.

### Tier 3: Browser (requires cluster + Docker)

```bash
KUBECONFIG=~/.kube/slam-stack-config make test-browser
```

Runs Playwright inside `mcr.microsoft.com/playwright:v1.52.0-noble` Docker image.
Sets up port-forwards to dashboard, sample app, and Kanidm, then runs browser
specs that verify:
- Dashboard loads and renders
- REST API endpoints return correct JSON
- OIDC discovery endpoint returns valid configuration
- No console errors or failed asset loads
- Mobile responsive layout

## CI Pipeline

```
push/PR → static + policy + flux (per-flavor matrix) + unit + kind smoke
```

The kind smoke test creates a Kubernetes-in-Docker cluster, applies the minimal
flavor manifests, and verifies the API server, CoreDNS, and NetworkPolicy CRD.

## Policy Test Cases

| Fixture | Expectation | Tests |
|---------|------------|-------|
| `good-pod.yaml` | Passes all pod security + RBAC policies | non-root, read-only rootfs, dedicated SA, no automount, resource limits |
| `bad-privileged-pod.yaml` | Blocked | `privileged: true` container |
| `bad-root-user.yaml` | Blocked | `runAsUser: 0` |
| `bad-default-sa.yaml` | Blocked | uses `default` ServiceAccount |
| `bad-automount-sa.yaml` | Blocked | `automountServiceAccountToken` not false |
| `bad-writable-rootfs.yaml` | Blocked | `readOnlyRootFilesystem: false` |

## Adding New Tests

### Static analysis
Add new shell scripts or YAML manifests — they're automatically picked up
by `tests/static/run-all.sh`.

### Policy tests
1. Add a fixture to `tests/policy/cases/`
2. Add a `run_kyverno_test` call in `tests/policy/run-all.sh`

### Unit tests
Add `#[cfg(test)] mod tests { ... }` to any Rust source file.

### Browser tests
Add a `.spec.ts` file to `tests/browser/tests/`.

### Live endpoint checks
Add a `check_endpoint` call in `tests/e2e/endpoint-check.sh`.

## Requirements

- **Tier 1**: Docker, bash, make (kustomize for kubeconform)
- **Tier 2**: kubectl, kubeconfig pointing to a slam-stack cluster
- **Tier 3**: Docker, kubectl, kubeconfig
- **CI**: GitHub Actions runner (Ubuntu)

No host installs beyond Docker — all linting/validation tools are containerized
with pinned versions for deterministic results.
