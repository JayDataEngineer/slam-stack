#!/usr/bin/env bash
# Slam Stack — Matrix Flavor End-to-End Test
# Validates the full matrix stack works: Tuwunel → Cinny → LiveKit
# Run after: FLAVOR=matrix ./deploy.sh
# Requires: kubectl, curl, jq
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
info() { echo -e "${BLUE}[*]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

FAILED=0
MATRIX_NS="${MATRIX_NS:-matrix}"
TUWUNEL_SVC="tuwunel"
CINNY_SVC="cinny"
LIVEKIT_SVC="livekit"
REG_TOKEN="${REG_TOKEN:-changeme}"

echo "=== Slam Stack Matrix E2E ==="
echo ""

# === 1. Pod health ===
info "Checking pod health..."
for app in tuwunel cinny livekit livekit-redis; do
  POD=$(kubectl -n "$MATRIX_NS" get pod -l app="$app" -o name 2>/dev/null | head -1)
  if [ -z "$POD" ]; then
    fail "No pod found for $app"
    FAILED=$((FAILED + 1))
    continue
  fi
  READY=$(kubectl -n "$MATRIX_NS" get "$POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
  if [ "$READY" = "true" ]; then
    pass "$app running"
  else
    fail "$app not ready"
    FAILED=$((FAILED + 1))
  fi
done
echo ""

# === 2. Matrix client API ===
info "Testing Matrix client API..."
TUWUNEL_POD=$(kubectl -n "$MATRIX_NS" get pod -l app=tuwunel -o name 2>/dev/null | head -1)
if [ -n "$TUWUNEL_POD" ]; then
  VERSIONS=$(kubectl -n "$MATRIX_NS" exec "$TUWUNEL_POD" -c tuwunel -- \
    curl -s http://localhost:8008/_matrix/client/versions 2>/dev/null || true)
  if echo "$VERSIONS" | grep -q "versions"; then
    pass "Matrix client API responds"
  else
    fail "Matrix client API did not respond"
    FAILED=$((FAILED + 1))
  fi
fi
echo ""

# === 3. Cinny web UI ===
info "Testing Cinny web UI..."
CINNY_POD=$(kubectl -n "$MATRIX_NS" get pod -l app=cinny -o name 2>/dev/null | head -1)
if [ -n "$CINNY_POD" ]; then
  HTTP_CODE=$(kubectl -n "$MATRIX_NS" exec "$CINNY_POD" -- \
    wget -q -O /dev/null --timeout=5 http://localhost:80/ 2>/dev/null && echo 200 || echo 0)
  if [ "$HTTP_CODE" = "200" ]; then
    pass "Cinny web UI responds on :80"
  else
    fail "Cinny web UI not responding"
    FAILED=$((FAILED + 1))
  fi

  CONFIG_JSON=$(kubectl -n "$MATRIX_NS" exec "$CINNY_POD" -- \
    cat /usr/share/nginx/html/config.json 2>/dev/null || true)
  if echo "$CONFIG_JSON" | grep -q "homeserverList"; then
    pass "Cinny config.json has homeserver configured"
  else
    fail "Cinny config.json missing homeserver config"
    FAILED=$((FAILED + 1))
  fi
fi
echo ""

# === 4. Tuwunel config ===
info "Checking Tuwunel configuration..."
TUWUNEL_CFG=$(kubectl -n "$MATRIX_NS" get configmap tuwunel-config -o jsonpath='{.data.tuwunel\.toml}' 2>/dev/null || true)
if echo "$TUWUNEL_CFG" | grep -q "allow_federation = false"; then
  pass "Federation disabled"
else
  fail "Federation not explicitly disabled"
  FAILED=$((FAILED + 1))
fi
if echo "$TUWUNEL_CFG" | grep -q "registration_tokens"; then
  pass "Registration tokens enabled"
else
  warn "Registration tokens not configured"
fi
echo ""

# === 5. Cilium network policies ===
info "Checking Cilium policies for matrix namespace..."
POLICY_COUNT=$(kubectl get cnp -n "$MATRIX_NS" --no-headers 2>/dev/null | wc -l)
if [ "$POLICY_COUNT" -ge 4 ]; then
  pass "Cilium policies applied ($POLICY_COUNT CNP in matrix namespace)"
else
  warn "Expected 4+ Cilium policies in $MATRIX_NS, found $POLICY_COUNT"
fi
for policy in allow-to-tuwunel allow-to-cinny allow-to-livekit allow-to-livekit-redis; do
  if kubectl get cnp -n "$MATRIX_NS" "$policy" &>/dev/null; then
    pass "  Policy: $policy"
  else
    warn "  Policy missing: $policy"
  fi
done
echo ""

# === 6. TLS certificates ===
info "Checking TLS certificates..."
for cert in matrix-tls livekit-tls; do
  READY=$(kubectl get certificate -n "$MATRIX_NS" "$cert" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  if [ "$READY" = "True" ]; then
    pass "Certificate $cert issued"
  else
    warn "Certificate $cert not yet ready (cert-manager may still be issuing)"
  fi
done
echo ""

# === 7. ServiceAccounts ===
info "Checking ServiceAccounts..."
for sa in tuwunel cinny livekit; do
  if kubectl get sa -n "$MATRIX_NS" "$sa" &>/dev/null; then
    pass "ServiceAccount $sa exists"
  else
    fail "ServiceAccount $sa missing"
    FAILED=$((FAILED + 1))
  fi
done
echo ""

# === 8. Matrix functional test (register, login, room, message) ===
info "Running Matrix functional test..."
TUWUNEL_CLI="kubectl -n $MATRIX_NS exec $TUWUNEL_POD -c tuwunel -- curl -s"
# Check server versions
SERVER_OK=$($TUWUNEL_CLI http://localhost:8008/_matrix/client/versions 2>/dev/null | jq -r '.versions[0]' 2>/dev/null || true)
if [ -n "$SERVER_OK" ]; then
  pass "Matrix server version: $SERVER_OK"
else
  warn "Could not determine Matrix server version"
fi

# Try to register a test user (this may fail with registrations closed, that's OK)
REG_RESP=$($TUWUNEL_CLI -X POST http://localhost:8008/_matrix/client/v3/register \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"e2e-test-$(date +%s)\",\"password\":\"test1234\",\"auth\":{\"type\":\"m.login.registration_token\",\"token\":\"$REG_TOKEN\"}}" 2>/dev/null || true)
REG_ERR=$(echo "$REG_RESP" | jq -r '.errcode // empty' 2>/dev/null || true)
if [ "$REG_ERR" = "M_FORBIDDEN" ]; then
  warn "Registration blocked (expected with public registration disabled)"
  warn "  Manually set up registration tokens in tuwunel.toml"
elif [ -n "$REG_ERR" ]; then
  warn "Registration API error: $REG_ERR"
elif [ -n "$REG_RESP" ]; then
  pass "User registration succeeded"
  # Extract access token
  ACCESS_TOKEN=$(echo "$REG_RESP" | jq -r '.access_token // empty' 2>/dev/null || true)
  if [ -n "$ACCESS_TOKEN" ]; then
    # Create a room
    ROOM_RESP=$($TUWUNEL_CLI -X POST http://localhost:8008/_matrix/client/v3/createRoom \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"name":"e2e-test-room","preset":"private_chat"}' 2>/dev/null || true)
    ROOM_ID=$(echo "$ROOM_RESP" | jq -r '.room_id // empty' 2>/dev/null || true)
    if [ -n "$ROOM_ID" ]; then
      pass "Room created: $ROOM_ID"
      # Send a message
      MSG_RESP=$($TUWUNEL_CLI -X POST "http://localhost:8008/_matrix/client/v3/rooms/$ROOM_ID/send/m.room.message" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"msgtype":"m.text","body":"e2e test message"}' 2>/dev/null || true)
      EVENT_ID=$(echo "$MSG_RESP" | jq -r '.event_id // empty' 2>/dev/null || true)
      if [ -n "$EVENT_ID" ]; then
        pass "Message sent: $EVENT_ID"
      else
        fail "Failed to send message"
        FAILED=$((FAILED + 1))
      fi
    else
      fail "Failed to create room"
      FAILED=$((FAILED + 1))
    fi
  fi
fi
echo ""

# === Summary ===
echo "=== Results ==="
if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}All Matrix E2E checks passed.${NC}"
  echo "  Web UI:  https://matrix.slamstack.internal (via Headscale)"
  echo "  Client:  https://matrix.slamstack.internal (homeserver URL for Element X)"
else
  echo -e "${RED}$FAILED check(s) failed.${NC}"
fi
