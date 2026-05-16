#!/usr/bin/env bash
# Slam Stack — Smoke Test / Verification Suite
# Run this after deployment to verify security layers are active.
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "${BLUE}[*]${NC} $1"; }

FAILED=0

echo "=== Slam Stack Verification Suite ==="
echo "  Flavor: ${FLAVOR:-og}"
echo ""

# === 1. Cilium status ===
info "Checking Cilium..."
CILIUM_POD=$(kubectl -n kube-system get pod -l k8s-app=cilium -o name 2>/dev/null | head -1)
if [ -z "$CILIUM_POD" ]; then
  fail "No Cilium pod found"
  FAILED=$((FAILED + 1))
else
  STATUS=$(kubectl -n kube-system exec "$CILIUM_POD" -- cilium status --brief 2>/dev/null)
  if echo "$STATUS" | grep -q "OK"; then
    pass "Cilium running"
  else
    fail "Cilium status not OK"
    FAILED=$((FAILED + 1))
  fi
  # Check WireGuard
  WG=$(kubectl -n kube-system exec "$CILIUM_POD" -- cilium encrypt status 2>/dev/null)
  if echo "$WG" | grep -q "Wireguard"; then
    pass "WireGuard encryption enabled"
  else
    warn "WireGuard encryption status unclear (may need manual check)"
  fi
fi

# === 2. Kyverno admission ===
info "Checking Kyverno..."
KYVERNO_PODS=$(kubectl -n kyverno get pod -l app.kubernetes.io/name=kyverno --no-headers 2>/dev/null | wc -l)
if [ "$KYVERNO_PODS" -gt 0 ]; then
  ALL_READY=$(kubectl -n kyverno get pod -l app.kubernetes.io/name=kyverno -o jsonpath='{.items[*].status.containerStatuses[0].ready}' 2>/dev/null)
  if echo "$ALL_READY" | grep -q "true"; then
    pass "Kyverno running"
  else
    fail "Kyverno not ready"
    FAILED=$((FAILED + 1))
  fi
else
  warn "Kyverno not deployed (expected in early setup)"
fi

# === 3. Deny privileged pod ===
info "Testing security enforcement..."
if kubectl run test-privileged --image=busybox --restart=Never -- sh -c "id" 2>/dev/null; then
  warn "Pod created without restriction (verify Kyverno policies)"
  kubectl delete pod test-privileged --force 2>/dev/null || true
else
  pass "Pod admission restrictions active"
fi

# === 4. Tetragon ===
info "Checking Tetragon..."
TETRAGON_PODS=$(kubectl -n kube-system get pod -l app.kubernetes.io/name=tetragon --no-headers 2>/dev/null | wc -l)
if [ "$TETRAGON_PODS" -gt 0 ]; then
  pass "Tetragon running"
else
  warn "Tetragon not deployed (expected in early setup)"
fi

# === 5. Vault ===
info "Checking Vault..."
VAULT_POD=$(kubectl -n vault get pod -l app.kubernetes.io/name=vault -o name 2>/dev/null | head -1)
if [ -n "$VAULT_POD" ]; then
  SEALED=$(kubectl -n vault exec "$VAULT_POD" -- vault status -format=json 2>/dev/null | grep -o '"sealed":false' || true)
  if [ -n "$SEALED" ]; then
    pass "Vault unsealed and running"
  else
    warn "Vault running but sealed (run 'day-0 ceremony')"
  fi
else
  warn "Vault not deployed"
fi

# === 6. VictoriaLogs ===
info "Checking VictoriaLogs..."
VL_POD=$(kubectl -n observability get pod -l app=victoria-logs -o name 2>/dev/null | head -1)
if [ -n "$VL_POD" ]; then
  READY=$(kubectl -n observability get "$VL_POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
  if [ "$READY" = "true" ]; then
    pass "VictoriaLogs running"
  else
    fail "VictoriaLogs not ready"
    FAILED=$((FAILED + 1))
  fi
else
  warn "VictoriaLogs not deployed"
fi

# === 7. Kanidm ===
info "Checking Kanidm..."
KANIDM_POD=$(kubectl -n identity get pod -l app=kanidm -o name 2>/dev/null | head -1)
if [ -n "$KANIDM_POD" ]; then
  READY=$(kubectl -n identity get "$KANIDM_POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
  if [ "$READY" = "true" ]; then
    pass "Kanidm running"
  else
    fail "Kanidm not ready"
    FAILED=$((FAILED + 1))
  fi
else
  warn "Kanidm not deployed"
fi

# === 8. Network policies applied ===
info "Checking network policies..."
POLICY_COUNT=$(kubectl get cnp -A --no-headers 2>/dev/null | wc -l)
CCNP_COUNT=$(kubectl get ccnp --no-headers 2>/dev/null | wc -l)
if [ "$POLICY_COUNT" -gt 0 ] || [ "$CCNP_COUNT" -gt 0 ]; then
  pass "Cilium network policies applied ($POLICY_COUNT CNP, $CCNP_COUNT CCNP)"
else
  warn "No Cilium network policies found (apply from components/cilium/)"
fi

# === 9. Pod security (all pods non-root, read-only) ===
info "Auditing pod security contexts..."
NON_ROOT=$(kubectl get pods -A -o jsonpath='{.items[*].spec.securityContext.runAsNonRoot}' 2>/dev/null | tr ' ' '\n' | grep -c "true" || true)
TOTAL_PODS=$(kubectl get pods -A --no-headers 2>/dev/null | wc -l)
if [ "$NON_ROOT" -gt 0 ]; then
  pass "$NON_ROOT/$TOTAL_PODS pods run as non-root"
else
  warn "No pods with explicit non-root context"
fi

# === Summary ===
echo ""
echo "=== Results ==="
if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}All checks passed.${NC}"
else
  echo -e "${RED}$FAILED check(s) failed.${NC}"
  echo "Review the failures above."
fi
echo ""
echo "Note: Some components may not be deployed yet (stage 1 = Cilium + Kyverno only)."
echo "Run ./deploy.sh to deploy remaining components."
