#!/usr/bin/env bash
# Slam Stack — Matrix Flavor End-to-End Test
# Validates the full matrix stack: Tuwunel → Cinny → LiveKit → Kanidm OIDC
# Run after: FLAVOR=matrix ./deploy.sh
# Requires: kubectl, curl, jq
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
pass() { echo -e "  ${GREEN}PASS${NC} $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; FAILED=$((FAILED + 1)); }
info() { echo -e "${BLUE}[*]${NC} $1"; }
warn() { echo -e "  ${YELLOW}WARN${NC} $1"; }

FAILED=0
MATRIX_NS="${MATRIX_NS:-matrix}"
IDENTITY_NS="${IDENTITY_NS:-identity}"
REG_TOKEN="${REG_TOKEN:-changeme}"

echo "=== Slam Stack Matrix E2E ==="
echo ""

# Helper: run curl inside a pod's network
# shellcheck disable=SC2329  # invoked indirectly
run_in_pod() {
  local ns="$1" pod="$2"
  shift 2
  kubectl -n "$ns" exec "$pod" -- "$@" 2>/dev/null
}

# ─── 1. Pod health ─────────────────────────────────────────────
info "1. Pod health"
for app in tuwunel cinny; do
  POD=$(kubectl -n "$MATRIX_NS" get pod -l app="$app" -o name 2>/dev/null | head -1)
  if [ -z "$POD" ]; then
    fail "$app — no pod found"
    continue
  fi
  READY=$(kubectl -n "$MATRIX_NS" get "$POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
  if [ "$READY" = "true" ]; then
    pass "$app running"
  else
    fail "$app not ready"
  fi
done

# Kanidm
KANIDM_POD=$(kubectl -n "$IDENTITY_NS" get pod -l app=kanidm -o name 2>/dev/null | head -1)
if [ -n "$KANIDM_POD" ]; then
  READY=$(kubectl -n "$IDENTITY_NS" get "$KANIDM_POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
  if [ "$READY" = "true" ]; then pass "kanidm running"; else fail "kanidm not ready"; fi
else
  fail "kanidm — no pod found"
fi

# LiveKit (optional)
LK_POD=$(kubectl -n "$MATRIX_NS" get pod -l app=livekit -o name 2>/dev/null | head -1)
if [ -n "$LK_POD" ]; then
  READY=$(kubectl -n "$MATRIX_NS" get "$LK_POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
  if [ "$READY" = "true" ]; then pass "livekit running"; else warn "livekit not ready (optional)"; fi
else
  warn "livekit not deployed (optional)"
fi
echo ""

# ─── 2. Tuwunel Matrix API ─────────────────────────────────────
info "2. Tuwunel Matrix API"
TUWUNEL_POD=$(kubectl -n "$MATRIX_NS" get pod -l app=tuwunel -o name 2>/dev/null | head -1 | sed 's|pod/||')
if [ -n "$TUWUNEL_POD" ]; then
  VERSIONS=$(kubectl -n "$MATRIX_NS" exec "$TUWUNEL_POD" -c tuwunel -- \
    curl -sf http://localhost:8008/_matrix/client/versions 2>/dev/null || true)
  if echo "$VERSIONS" | grep -q '"versions"'; then
    pass "Client API responds"
    # Check OIDC support (MSC2964/2965/2966)
    for msc in org.matrix.msc2964 org.matrix.msc2965 org.matrix.msc2966; do
      if echo "$VERSIONS" | grep -q "$msc"; then
        pass "$msc supported"
      else
        fail "$msc not advertised — OIDC may not work"
      fi
    done
  else
    fail "Client API did not respond"
  fi
else
  fail "No Tuwunel pod found"
fi
echo ""

# ─── 3. Cinny web UI ───────────────────────────────────────────
info "3. Cinny web UI"
CINNY_POD=$(kubectl -n "$MATRIX_NS" get pod -l app=cinny -o name 2>/dev/null | head -1 | sed 's|pod/||')
if [ -n "$CINNY_POD" ]; then
  BODY=$(kubectl -n "$MATRIX_NS" exec "$CINNY_POD" -- \
    curl -sf http://localhost:80/ 2>/dev/null || true)
  if echo "$BODY" | grep -q "cinny"; then
    pass "Cinny serves HTML"
  else
    fail "Cinny not serving expected content"
  fi
  CONFIG=$(kubectl -n "$MATRIX_NS" exec "$CINNY_POD" -- \
    cat /usr/share/nginx/html/config.json 2>/dev/null || true)
  if echo "$CONFIG" | grep -q "homeserverList"; then
    pass "config.json has homeserver list"
  else
    fail "config.json missing homeserver config"
  fi
else
  fail "No Cinny pod found"
fi
echo ""

# ─── 4. Kanidm OIDC provider ──────────────────────────────────
info "4. Kanidm OIDC provider"
if [ -n "$KANIDM_POD" ]; then
  KANIDM_POD_NAME=${KANIDM_POD#pod/}

  # Health check
  STATUS=$(kubectl -n "$IDENTITY_NS" exec "$KANIDM_POD_NAME" -- \
    curl -skf https://localhost:443/status 2>/dev/null || true)
  if [ "$STATUS" = "true" ]; then
    pass "Kanidm health check OK"
  else
    fail "Kanidm health check failed"
  fi

  # OIDC discovery for tuwunel client
  DISCOVERY=$(kubectl -n "$IDENTITY_NS" exec "$KANIDM_POD_NAME" -- \
    curl -skf https://localhost:443/oauth2/openid/tuwunel/.well-known/openid-configuration 2>/dev/null || true)
  if echo "$DISCOVERY" | grep -q "authorization_endpoint"; then
    pass "OIDC discovery document served"
    ISSUER=$(echo "$DISCOVERY" | tr ',' '\n' | grep '"issuer"' | head -1)
    pass "Issuer: $ISSUER"
  else
    fail "OIDC discovery failed — OAuth2 client 'tuwunel' may not be registered"
  fi
else
  fail "No Kanidm pod — cannot test OIDC"
fi
echo ""

# ─── 5. OIDC end-to-end flow ──────────────────────────────────
info "5. OIDC auth flow (authorization URL)"
if [ -n "$KANIDM_POD" ] && [ -n "$TUWUNEL_POD" ]; then
  KANIDM_POD_NAME=${KANIDM_POD#pod/}

  # Check that the authorize endpoint is reachable (returns a page, not 404)
  AUTH_RESP=$(kubectl -n "$IDENTITY_NS" exec "$KANIDM_POD_NAME" -- \
    curl -skf -o /dev/null -w "%{http_code}" \
    "https://localhost:443/ui/oauth2?client_id=tuwunel&redirect_uri=https://matrix.slamstack.internal&response_type=code&scope=openid+profile+email" \
    2>/dev/null || true)
  if [ "$AUTH_RESP" = "200" ] || [ "$AUTH_RESP" = "302" ]; then
    pass "OAuth2 authorize endpoint reachable ($AUTH_RESP)"
  else
    warn "OAuth2 authorize returned $AUTH_RESP (may need admin login first)"
  fi

  # Verify Tuwunel can reach Kanidm internally
  KANIDM_SVC_IP=$(kubectl -n "$IDENTITY_NS" get svc kanidm -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
  if [ -n "$KANIDM_SVC_IP" ]; then
    INTERNAL_OK=$(kubectl -n "$MATRIX_NS" exec "$TUWUNEL_POD" -c tuwunel -- \
      curl -skf -o /dev/null -w "%{http_code}" "https://$KANIDM_SVC_IP:443/status" 2>/dev/null || true)
    if [ "$INTERNAL_OK" = "200" ]; then
      pass "Tuwunel → Kanidm internal connectivity OK"
    else
      fail "Tuwunel cannot reach Kanidm internally (got $INTERNAL_OK)"
    fi
  fi
else
  warn "Skipping OIDC flow test — missing pods"
fi
echo ""

# ─── 6. Tuwunel OIDC config ───────────────────────────────────
info "6. Tuwunel OIDC configuration"
TUWUNEL_CFG=$(kubectl -n "$MATRIX_NS" get configmap tuwunel-config -o jsonpath='{.data.tuwunel\.toml}' 2>/dev/null || true)
if [ -n "$TUWUNEL_CFG" ]; then
  # Check for OIDC section (supports both [global.oauth] and [oauth2] formats)
  if echo "$TUWUNEL_CFG" | grep -qi "oidc\|oauth"; then
    pass "OIDC/OAuth2 section present in config"
    # Verify key fields
    for field in issuer client_id client_secret scopes; do
      if echo "$TUWUNEL_CFG" | grep -qi "$field"; then
        pass "  $field configured"
      else
        fail "  $field missing from config"
      fi
    done
  else
    fail "No OIDC/OAuth2 section in Tuwunel config"
  fi

  # Security checks
  if echo "$TUWUNEL_CFG" | grep -q "allow_federation = false"; then
    pass "Federation disabled"
  else
    warn "Federation not explicitly disabled"
  fi
  if echo "$TUWUNEL_CFG" | grep -q "allow_registration = true"; then
    if echo "$TUWUNEL_CFG" | grep -q "registration_token"; then
      pass "Registration gated by token"
    else
      warn "Registration open without token guard"
    fi
  fi
else
  fail "Could not read Tuwunel config"
fi
echo ""

# ─── 7. Secrets and credentials ────────────────────────────────
info "7. Secrets and credentials"
# OAuth2 client secret
if kubectl -n "$MATRIX_NS" get secret tuwunel-oidc -o jsonpath='{.data.oidc_client_secret}' 2>/dev/null | base64 -d >/dev/null 2>&1; then
  pass "tuwunel-oidc secret exists with oidc_client_secret"
else
  warn "tuwunel-oidc secret missing — OIDC client may not be registered in Kanidm"
fi

# TLS certs
for cert in kanidm-tls tuwunel-tls; do
  NS="$IDENTITY_NS"
  [ "$cert" = "tuwunel-tls" ] && NS="$MATRIX_NS"
  READY=$(kubectl get certificate -n "$NS" "$cert" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  if [ "$READY" = "True" ]; then
    pass "Certificate $cert issued"
  else
    warn "Certificate $cert not ready (cert-manager may be issuing)"
  fi
done
echo ""

# ─── 8. Network policies ──────────────────────────────────────
info "8. Network policies"
POLICY_COUNT=$(kubectl get cnp -n "$MATRIX_NS" --no-headers 2>/dev/null | wc -l)
if [ "$POLICY_COUNT" -ge 3 ]; then
  pass "Cilium policies applied ($POLICY_COUNT in $MATRIX_NS)"
else
  warn "Expected 3+ Cilium policies, found $POLICY_COUNT"
fi
echo ""

# ─── 9. Matrix functional test ────────────────────────────────
info "9. Matrix functional test (register → login → room → message)"
if [ -n "$TUWUNEL_POD" ]; then
  CLI="kubectl -n $MATRIX_NS exec $TUWUNEL_POD -c tuwunel -- curl -s"

  # Register a test user
  TIMESTAMP=$(date +%s)
  REG_RESP=$($CLI -X POST http://localhost:8008/_matrix/client/v3/register \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"e2e-${TIMESTAMP}\",\"password\":\"Test1234!\",\"auth\":{\"type\":\"m.login.registration_token\",\"token\":\"$REG_TOKEN\"}}" 2>/dev/null || true)
  REG_ERR=$(echo "$REG_RESP" | jq -r '.errcode // empty' 2>/dev/null || true)

  if [ "$REG_ERR" = "M_FORBIDDEN" ]; then
    warn "Registration blocked (public registration disabled — expected)"
  elif [ -n "$REG_ERR" ]; then
    warn "Registration error: $REG_ERR"
  elif echo "$REG_RESP" | grep -q "access_token"; then
    pass "User registration succeeded"
    ACCESS_TOKEN=$(echo "$REG_RESP" | jq -r '.access_token // empty' 2>/dev/null || true)

    if [ -n "$ACCESS_TOKEN" ]; then
      # Create a room
      ROOM_RESP=$($CLI -X POST http://localhost:8008/_matrix/client/v3/createRoom \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"name":"e2e-test","preset":"private_chat"}' 2>/dev/null || true)
      ROOM_ID=$(echo "$ROOM_RESP" | jq -r '.room_id // empty' 2>/dev/null || true)

      if [ -n "$ROOM_ID" ]; then
        pass "Room created: $ROOM_ID"

        # Send a message
        TXN_ID="txn-$(date +%s)"
        MSG_RESP=$($CLI -X PUT "http://localhost:8008/_matrix/client/v3/rooms/$ROOM_ID/send/m.room.message/$TXN_ID" \
          -H "Authorization: Bearer $ACCESS_TOKEN" \
          -H "Content-Type: application/json" \
          -d '{"msgtype":"m.text","body":"e2e test message from slam-stack"}' 2>/dev/null || true)
        EVENT_ID=$(echo "$MSG_RESP" | jq -r '.event_id // empty' 2>/dev/null || true)

        if [ -n "$EVENT_ID" ]; then
          pass "Message sent: $EVENT_ID"
        else
          fail "Failed to send message"
        fi

        # Sync and verify message comes back
        SYNC_RESP=$($CLI "http://localhost:8008/_matrix/client/v3/sync?timeout=1000" \
          -H "Authorization: Bearer $ACCESS_TOKEN" 2>/dev/null || true)
        if echo "$SYNC_RESP" | grep -q "e2e test message"; then
          pass "Message received via sync"
        else
          warn "Message not yet visible in sync (may need a moment)"
        fi
      else
        fail "Failed to create room"
      fi
    fi
  else
    warn "Registration response unclear"
  fi
else
  warn "Skipping functional test — no Tuwunel pod"
fi
echo ""

# ─── 10. ServiceAccounts ──────────────────────────────────────
info "10. ServiceAccounts"
for sa in tuwunel cinny; do
  if kubectl get sa -n "$MATRIX_NS" "$sa" &>/dev/null; then
    pass "ServiceAccount $sa exists"
  else
    fail "ServiceAccount $sa missing"
  fi
done
echo ""

# ─── Summary ──────────────────────────────────────────────────
echo "=== Results ==="
if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}All Matrix E2E checks passed.${NC}"
else
  echo -e "${RED}$FAILED check(s) failed.${NC}"
fi
exit $FAILED
