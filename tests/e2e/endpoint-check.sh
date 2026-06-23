#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Tier 2: Live cluster endpoint checks.
#
# Requires a running slam-stack cluster. Non-mocked proof that every
# in-cluster service responds on its HTTP endpoint. Uses kubectl port-forward
# to reach services directly — no Ingress/TLS setup needed.
#
# Usage:
#   KUBECONFIG=~/.kube/slam-stack-config ./endpoint-check.sh
#   KUBECONFIG=... FLAVOR=rust ./endpoint-check.sh
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/slam-stack-config}"
FLAVOR="${FLAVOR:-og}"
TIMEOUT="${TIMEOUT:-30}"   # seconds per port-forward

export KUBECONFIG

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${BLUE}[*]${NC} $1"; }
pass()  { echo -e "  ${GREEN}PASS${NC} $1"; }
fail()  { echo -e "  ${RED}FAIL${NC} $1"; }
skip()  { echo -e "  ${YELLOW}SKIP${NC} $1"; }

FAILED=0
SKIPPED=0
PASSED=0

# ─── Preflight ────────────────────────────────────────────────────────────
if ! command -v kubectl &>/dev/null; then
  echo -e "${RED}ERROR: kubectl not found${NC}"
  exit 1
fi

if ! kubectl cluster-info &>/dev/null; then
  echo -e "${RED}ERROR: Cannot reach cluster with KUBECONFIG=$KUBECONFIG${NC}"
  exit 1
fi

info "Live cluster endpoint checks — flavor: $FLAVOR"
info "Cluster: $(kubectl config current-context 2>/dev/null || echo 'unknown')"
echo ""

# ─── Port-forward helper ──────────────────────────────────────────────────
# Args: namespace service_name target_port local_port
# Sets __PF_PID to the port-forward PID.
port_forward() {
  local ns="$1" svc="$2" target="$3" local_port="$4"
  kubectl -n "$ns" port-forward "svc/$svc" "${local_port}:${target}" >/dev/null 2>&1 &
  __PF_PID=$!
  # Wait for the port to be ready.
  for _ in $(seq 1 "$TIMEOUT"); do
    if curl -sf -o /dev/null "http://127.0.0.1:${local_port}" 2>/dev/null \
       || curl -sf -k -o /dev/null "https://127.0.0.1:${local_port}" 2>/dev/null; then
      return 0
    fi
    if ! kill -0 "$__PF_PID" 2>/dev/null; then
      return 1
    fi
    sleep 1
  done
  return 1
}

kill_pf() {
  [ -n "${__PF_PID:-}" ] && kill "$__PF_PID" 2>/dev/null || true
  wait "$__PF_PID" 2>/dev/null || true
  __PF_PID=""
}

# ─── Endpoint checker ─────────────────────────────────────────────────────
# Args: label namespace service port path expected_substring [use_https]
check_endpoint() {
  local label="$1" ns="$2" svc="$3" port="$4" path="$5" expected="$6" use_https="${7:-false}"
  local local_port=$((RANDOM % 10000 + 30000))

  # Check if the service exists.
  if ! kubectl -n "$ns" get svc "$svc" &>/dev/null; then
    skip "$label (service $ns/$svc not deployed in $FLAVOR flavor)"
    SKIPPED=$((SKIPPED + 1))
    return
  fi

  if ! port_forward "$ns" "$svc" "$port" "$local_port"; then
    fail "$label — port-forward to $ns/$svc:$port failed"
    kill_pf
    FAILED=$((FAILED + 1))
    return
  fi

  local scheme="http"
  [ "$use_https" = "true" ] && scheme="https"

  local url="${scheme}://127.0.0.1:${local_port}${path}"
  local body
  body=$(curl -sf -k --max-time 10 "$url" 2>/dev/null || echo "")

  kill_pf

  if [ -n "$body" ] && echo "$body" | grep -qi "$expected"; then
    pass "$label"
    PASSED=$((PASSED + 1))
  else
    fail "$label — expected '$expected' in response from $url"
    echo "         got: ${body:0:120}"
    FAILED=$((FAILED + 1))
  fi
}

# ─── Kubernetes API health (always available) ─────────────────────────────
info "Kubernetes control plane"
API_OK=$(kubectl get --raw='/healthz' 2>/dev/null || echo "")
if [ "$API_OK" = "ok" ]; then
  pass "kube-apiserver /healthz"
  PASSED=$((PASSED + 1))
else
  fail "kube-apiserver /healthz"
  FAILED=$((FAILED + 1))
fi

NODES_READY=$(kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | tr ' ' '\n' | grep -c "True" || echo 0)
TOTAL_NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
if [ "$NODES_READY" -eq "$TOTAL_NODES" ] && [ "$TOTAL_NODES" -gt 0 ]; then
  pass "$NODES_READY/$TOTAL_NODES nodes Ready"
  PASSED=$((PASSED + 1))
else
  fail "$NODES_READY/$TOTAL_NODES nodes Ready"
  FAILED=$((FAILED + 1))
fi
echo ""

# ─── Core system services ─────────────────────────────────────────────────
info "Core system pods"
for ns in kube-system flux-system; do
  PODS=$(kubectl -n "$ns" get pods --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
  if [ "$PODS" -gt 0 ]; then
    pass "$ns — $PODS pods Running"
    PASSED=$((PASSED + 1))
  else
    fail "$ns — no Running pods"
    FAILED=$((FAILED + 1))
  fi
done
echo ""

# ─── Service endpoints by flavor ──────────────────────────────────────────
info "Application endpoints (port-forward + curl)"

# Cilium (always present in all flavors)
check_endpoint "Cilium health" kube-system hubble-metrics 9965 /metrics "cilium" || true
check_endpoint "Cilium relay"  kube-system hubble-relay    80  / "" false || true

# Web dashboard (core+ flavors)
check_endpoint "Web dashboard"    web           slam-stack-web  8080 /            "slam"  || true

# Kanidm identity (core+ flavors)
check_endpoint "Kanidm UI"        identity      kanidm           8443 /            "" true || true
check_endpoint "Kanidm OAuth"     identity      kanidm           8443 /oauth2/openid/slam-stack/.well-known/openid-configuration "issuer" true || true

# RustFS (og+ flavors)
check_endpoint "RustFS S3 health" storage       rustfs           9000 /health      "ok"   || true

# Stalwart mail (og+ flavors)
check_endpoint "Stalwart SMTP banner" mail     stalwart         8080 /            ""     || true

# Matrix / Tuwunel (matrix+ flavors)
check_endpoint "Tuwunel Matrix client" matrix  tuwunel          8008 /_matrix/client/versions "versions" || true

# Commet (commet+ flavors)
check_endpoint "Commet web UI"    commet        commet           80   /            ""     || true

# Sample Rust workload (rust flavor)
check_endpoint "Sample app healthz" workload sample-rust-app    8080 /healthz      "ok"   || true
check_endpoint "Sample app hello"   workload sample-rust-app    8080 "/api/v1/hello?name=Test" "Hello" || true

echo ""

# ─── Network policy enforcement ───────────────────────────────────────────
info "Network policy enforcement"
NP_COUNT=$(kubectl get networkpolicies -A --no-headers 2>/dev/null | wc -l)
if [ "$NP_COUNT" -ge 1 ]; then
  pass "$NP_COUNT NetworkPolicies active"
  PASSED=$((PASSED + 1))
else
  fail "No NetworkPolicies found — default-deny not enforced"
  FAILED=$((FAILED + 1))
fi

# ─── Kyverno policies active ──────────────────────────────────────────────
CP_COUNT=$(kubectl get clusterpolicies.kyverno.io --no-headers 2>/dev/null | wc -l)
if [ "$CP_COUNT" -ge 1 ]; then
  pass "$CP_COUNT Kyverno ClusterPolicies active"
  PASSED=$((PASSED + 1))
else
  skip "No Kyverno ClusterPolicies (not deployed in $FLAVOR?)"
  SKIPPED=$((SKIPPED + 1))
fi
echo ""

# ─── Summary ─────────────────────────────────────────────────────────────
TOTAL=$((PASSED + FAILED + SKIPPED))
echo -e "${BLUE}Results:${NC} $PASSED passed, $FAILED failed, $SKIPPED skipped ($TOTAL total)"
if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}=== All live endpoint checks passed ===${NC}"
  exit 0
else
  echo -e "${RED}=== $FAILED endpoint check(s) failed ===${NC}"
  exit 1
fi
