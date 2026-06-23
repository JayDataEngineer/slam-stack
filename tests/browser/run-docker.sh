#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Tier 3: Playwright browser tests via Docker.
#
# Sets up kubectl port-forwards to reach in-cluster services, then runs
# the mcr.microsoft.com/playwright container which has all browser deps.
#
# Usage:
#   ./run-docker.sh                         # All specs
#   ./run-docker.sh tests/dashboard.spec.ts # Specific spec
#   HEADED=1 ./run-docker.sh                # Headed mode (needs X11 forwarding)
#
# Required env:
#   KUBECONFIG  Path to kubeconfig (default: ~/.kube/slam-stack-config)
# Optional env:
#   BASE_URL         Dashboard URL (default: http://host.docker.internal:18080)
#   SAMPLE_APP_URL   Sample app URL (default: http://host.docker.internal:18081)
#   KANIDM_URL       Kanidm URL (default: http://host.docker.internal:18443)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/slam-stack-config}"
PLAYWRIGHT_IMAGE="${PLAYWRIGHT_IMAGE:-mcr.microsoft.com/playwright:v1.52.0-noble}"

export KUBECONFIG

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${BLUE}[*]${NC} $1"; }
pass() { echo -e "  ${GREEN}PASS${NC} $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; }

# ─── Preflight ────────────────────────────────────────────────────────────
if ! command -v kubectl &>/dev/null; then
  echo -e "${RED}ERROR: kubectl not found${NC}"
  exit 1
fi

if ! kubectl cluster-info &>/dev/null; then
  echo -e "${RED}ERROR: Cannot reach cluster with KUBECONFIG=$KUBECONFIG${NC}"
  exit 1
fi

if ! docker info &>/dev/null; then
  echo -e "${RED}ERROR: Docker daemon not available${NC}"
  exit 1
fi

# ─── Port-forward services ────────────────────────────────────────────────
# We forward to high-numbered localhost ports to avoid conflicts.
# The Playwright container reaches them via host.docker.internal.
PF_PIDS=()

setup_port_forward() {
  local label="$1" ns="$2" svc="$3" target_port="$4" local_port="$5"

  if ! kubectl -n "$ns" get svc "$svc" &>/dev/null; then
    echo -e "  ${YELLOW}SKIP${NC} $label (service $ns/$svc not found)"
    return 1
  fi

  info "Port-forward: $ns/$svc :${target_port} → localhost:${local_port}"
  kubectl -n "$ns" port-forward "svc/$svc" "${local_port}:${target_port}" >/dev/null 2>&1 &
  local pid=$!
  PF_PIDS+=("$pid")

  # Wait for it to be ready.
  for _ in $(seq 1 30); do
    if curl -sf -o /dev/null "http://127.0.0.1:${local_port}" 2>/dev/null \
       || curl -sf -k -o /dev/null "https://127.0.0.1:${local_port}" 2>/dev/null; then
      pass "$label port-forward ready"
      return 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      fail "$label — port-forward died"
      return 1
    fi
    sleep 1
  done
  fail "$label — port-forward timed out after 30s"
  return 1
}

# shellcheck disable=SC2329  # invoked via trap
cleanup() {
  info "Cleaning up port-forwards..."
  for pid in "${PF_PIDS[@]:-}"; do
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  done
  # Also kill any orphaned kubectl port-forward processes we spawned.
  pkill -f "kubectl.*port-forward.*svc/" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo ""
echo "=== Slam Stack Playwright Browser Tests ==="
echo "Container: $PLAYWRIGHT_IMAGE"
echo ""

# ─── Set up port-forwards ─────────────────────────────────────────────────
# Dashboard (web/slam-stack-web:8080 → localhost:18080)
setup_port_forward "Web Dashboard" web slam-stack-web 8080 18080 || true

# Sample app (workload/sample-rust-app:8080 → localhost:18081)
setup_port_forward "Sample App" workload sample-rust-app 8080 18081 || true

# Kanidm (identity/kanidm:8443 → localhost:18443)
setup_port_forward "Kanidm" identity kanidm 8443 18443 || true

echo ""

# ─── Run Playwright in Docker ─────────────────────────────────────────────
SPEC_ARGS="${*:-tests/}"

# Determine host.docker.internal IP for Linux Docker.
# On Docker Desktop this is built-in; on Linux we add --add-host.
HOST_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' || echo "172.17.0.1")

info "Running Playwright container..."
echo "  Specs:        $SPEC_ARGS"
echo "  Dashboard:    http://host.docker.internal:18080"
echo "  Sample App:   http://host.docker.internal:18081"
echo "  Kanidm:       http://host.docker.internal:18443"
echo ""

docker run --rm \
  --add-host "host.docker.internal:$HOST_IP" \
  -e "BASE_URL=http://host.docker.internal:18080" \
  -e "SAMPLE_APP_URL=http://host.docker.internal:18081" \
  -e "KANIDM_URL=http://host.docker.internal:18443" \
  -e "CI=${CI:-}" \
  -v "$SCRIPT_DIR:/work" -w /work \
  -v "$SCRIPT_DIR/test-results:/work/test-results" \
  "$PLAYWRIGHT_IMAGE" \
  /bin/bash -c "npx playwright install chromium 2>/dev/null; npx playwright test $SPEC_ARGS --reporter=list 2>&1" || {
    fail "Playwright tests failed"
    echo ""
    echo "HTML report: tests/browser/test-results/html-report/"
    echo "Screenshots: tests/browser/test-results/"
    exit 1
  }

echo ""
pass "All Playwright browser tests passed"
echo "  HTML report: tests/browser/test-results/html-report/"
echo "  JUnit XML:   tests/browser/test-results/junit.xml"
exit 0
