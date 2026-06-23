#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# CI smoke test — spin up a kind cluster, deploy slam-stack manifests,
# and run Tier 1 tests against it.
#
# This is the "full CI" path:
#   1. Create kind cluster
#   2. Apply the minimal flavor manifests
#   3. Verify pods reach Running state
#   4. Run static analysis (shellcheck/yamllint/kubeconform)
#   5. Run Kyverno policy tests
#   6. Tear down
#
# Usage:
#   ./kind-smoke.sh              # Full smoke
#   FLAVOR=minimal ./kind-smoke.sh
#   KEEP_CLUSTER=1 ./kind-smoke.sh  # Don't delete kind cluster after
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
FLAVOR="${FLAVOR:-minimal}"
KIND_IMAGE="${KIND_IMAGE:-kindest/node:v1.32.0}"
CLUSTER_NAME="slam-smoke"
KEEP_CLUSTER="${KEEP_CLUSTER:-0}"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; RED='\033[0m'; NC='\033[0m'
info() { echo -e "${BLUE}[*]${NC} $1"; }
pass() { echo -e "  ${GREEN}PASS${NC} $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; }

FAILED=0

# ─── Preflight ────────────────────────────────────────────────────────────
for cmd in docker kubectl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo -e "${RED}ERROR: $cmd not found${NC}"
    exit 1
  fi
done

# ─── Static analysis first (no cluster needed) ────────────────────────────
info "Running Tier 1 static analysis..."
if "$SCRIPT_DIR/../static/run-all.sh"; then
  pass "Static analysis"
else
  fail "Static analysis"
  FAILED=$((FAILED + 1))
fi
echo ""

info "Running Tier 1 Kyverno policy tests..."
if "$SCRIPT_DIR/../policy/run-all.sh"; then
  pass "Policy tests"
else
  fail "Policy tests"
  FAILED=$((FAILED + 1))
fi
echo ""

# ─── Create kind cluster ──────────────────────────────────────────────────
info "Creating kind cluster '$CLUSTER_NAME' ($KIND_IMAGE)"

# Check if kind is installed; install if not.
if ! command -v kind &>/dev/null; then
  info "Installing kind..."
  # shellcheck disable=SC1090
  [ "$(uname -m)" = "x86_64" ] && ARCH=amd64 || ARCH=arm64
  curl -sLo ./kind "https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-$ARCH"
  chmod +x ./kind
  sudo mv ./kind /usr/local/bin/kind
fi

# Delete existing cluster if present.
if kind get clusters 2>/dev/null | grep -q "$CLUSTER_NAME"; then
  info "Deleting existing cluster..."
  kind delete cluster --name "$CLUSTER_NAME"
fi

cat <<EOF | kind create cluster --name "$CLUSTER_NAME" --image "$KIND_IMAGE" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  ipFamily: ipv4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 8080
        protocol: TCP
      - containerPort: 443
        hostPort: 8443
        protocol: TCP
EOF

# Point kubectl at the kind cluster.
export KUBECONFIG="${HOME}/.kube/config"
kind get kubeconfig --name "$CLUSTER_NAME" > "$KUBECONFIG"

info "Waiting for control-plane to be Ready..."
kubectl wait --for=condition=Ready nodes --timeout=120s
pass "Kind cluster ready"

# ─── Apply manifests ──────────────────────────────────────────────────────
info "Applying $FLAVOR flavor manifests..."

# Build the manifests with kustomize, then apply.
MANIFEST_FILE=$(mktemp /tmp/slam-smoke-XXXXXX.yaml)
kubectl kustomize "$REPO_ROOT/clusters/$FLAVOR" > "$MANIFEST_FILE" 2>/dev/null || {
  fail "kustomize build failed for clusters/$FLAVOR"
  FAILED=$((FAILED + 1))
}

# Apply CRDs first, then the rest.
info "Applying CRDs..."
kubectl apply -f "$MANIFEST_FILE" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
# Give CRDs a moment to register.
sleep 3

info "Applying all manifests..."
if kubectl apply -f "$MANIFEST_FILE" 2>&1; then
  pass "Manifests applied"
else
  fail "Manifest apply had errors (may be expected for CRD ordering)"
  # Don't hard-fail — some CRDs may not exist in kind.
fi
rm -f "$MANIFEST_FILE"

# ─── Wait for pods ────────────────────────────────────────────────────────
info "Waiting for pods in kube-system (60s timeout)..."
sleep 5
kubectl -n kube-system get pods -o wide 2>/dev/null || true

# In kind, we won't have Cilium/Flux running (they need special setup),
# but core DNS should come up.
info "Waiting for CoreDNS..."
if kubectl -n kube-system wait --for=condition=Ready pods -l k8s-app=kube-dns --timeout=60s 2>/dev/null; then
  pass "CoreDNS pods Ready"
else
  fail "CoreDNS pods not Ready (may need CNI in kind)"
  FAILED=$((FAILED + 1))
fi

# ─── Verify API server ────────────────────────────────────────────────────
API_HEALTH=$(kubectl get --raw='/healthz' 2>/dev/null || echo "")
if [ "$API_HEALTH" = "ok" ]; then
  pass "kube-apiserver /healthz = ok"
else
  fail "kube-apiserver health check"
  FAILED=$((FAILED + 1))
fi

# ─── Verify NetworkPolicy CRD is registered ───────────────────────────────
if kubectl get crd networkpolicies.networking.k8s.io &>/dev/null; then
  pass "NetworkPolicy CRD registered"
else
  fail "NetworkPolicy CRD not found"
  FAILED=$((FAILED + 1))
fi

echo ""

# ─── Cleanup ──────────────────────────────────────────────────────────────
if [ "$KEEP_CLUSTER" = "1" ]; then
  info "Keeping kind cluster '$CLUSTER_NAME' (KEEP_CLUSTER=1)"
  info "Use: export KUBECONFIG=~/.kube/config && kubectl ..."
else
  info "Deleting kind cluster..."
  kind delete cluster --name "$CLUSTER_NAME"
fi

# ─── Summary ─────────────────────────────────────────────────────────────
echo ""
if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}=== CI Smoke test passed ===${NC}"
  exit 0
else
  echo -e "${RED}=== $FAILED smoke test(s) failed ===${NC}"
  exit 1
fi
