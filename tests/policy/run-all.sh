#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Kyverno policy tests — validate that admission policies accept/reject
# resources correctly using kyverno-cli via Docker.
#
# For each policy under components/kyverno/:
#   - "good" resources (tests/policy/cases/*-good.yaml) must be ALLOWED
#   - "bad"  resources (tests/policy/cases/*-bad.yaml)  must be BLOCKED
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
KYVERNO_CLI_IMAGE="${KYVERNO_CLI_IMAGE:-ghcr.io/kyverno/kyverno-cli:v1.13.4}"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${BLUE}[*]${NC} $1"; }
pass() { echo -e "  ${GREEN}PASS${NC} $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; }

FAILED=0
CASES_DIR="$SCRIPT_DIR/cases"
POLICY_FILE="$REPO_ROOT/components/kyverno/signature-policy.yaml"
RBAC_POLICY_FILE="$REPO_ROOT/components/kyverno/rbac-policies.yaml"

# Kyverno CLI requires policies and resources on the mounted volume.
# We copy them into a temp dir that gets mounted into the container.
WORK_DIR=$(mktemp -d /tmp/slam-kyverno-XXXXXX)
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/policies" "$WORK_DIR/cases"
cp "$POLICY_FILE" "$WORK_DIR/policies/"
cp "$RBAC_POLICY_FILE" "$WORK_DIR/policies/"
cp "$CASES_DIR"/*.yaml "$WORK_DIR/cases/" 2>/dev/null || true
chmod -R a+rX "$WORK_DIR"

# ─── Test runner ──────────────────────────────────────────────────────────
# Arguments: $1 = test name, $2 = expected result (pass|fail), $3 = case file
run_kyverno_test() {
  local name="$1"
  local expect="$2"  # "pass" = resource should be allowed, "fail" = blocked
  local case_file="$3"

  local output
  output=$(docker run --rm \
    -v "$WORK_DIR:/work" -w /work \
    "$KYVERNO_CLI_IMAGE" \
    apply policies/ \
    --resource "cases/$case_file" \
    2>&1 || true)

  # Parse the kyverno summary line: "pass: N, fail: N, warn: N, error: N, skip: N"
  local fail_count error_count
  fail_count=$(echo "$output" | grep -oP 'fail: \K[0-9]+' || echo "0")
  error_count=$(echo "$output" | grep -oP 'error: \K[0-9]+' || echo "0")

  if [ "$expect" = "pass" ]; then
    # Resource should be admitted — fail count must be 0.
    if [ "$fail_count" -eq 0 ] && [ "$error_count" -eq 0 ]; then
      pass "$name — allowed (as expected)"
    else
      fail "$name — expected ALLOW but policy rejected it ($fail_count failures)"
      echo "$output" | grep -iE '(fail|violation|error|result)' | head -5 | sed 's/^/      /'
      FAILED=$((FAILED + 1))
    fi
  else
    # Resource should be blocked — fail count must be > 0.
    if [ "$fail_count" -gt 0 ]; then
      pass "$name — blocked (as expected, $fail_count policy violations)"
    else
      fail "$name — expected BLOCK but policy allowed it"
      echo "$output" | tail -5 | sed 's/^/      /'
      FAILED=$((FAILED + 1))
    fi
  fi
}

# Special test: verify a compliant pod passes ALL security policies except
# image signature verification (which requires a real signed image + registry).
# This is the closest to a "pass" test we can run offline.
run_compliant_pod_test() {
  local name="$1"
  local case_file="$2"

  local output
  output=$(docker run --rm \
    -v "$WORK_DIR:/work" -w /work \
    "$KYVERNO_CLI_IMAGE" \
    apply policies/ \
    --resource "cases/$case_file" \
    2>&1 || true)

  # The only acceptable failure is from the require-image-signature policy
  # (verifyImages requires real registry access). All other policy failures
  # (restrict-pod-security, deny-privileged, require-resource-limits,
  # restrict-service-account-tokens) indicate real violations.
  local non_sig_failures
  # grep -cv returns count of non-matching lines; || true guards pipefail.
  non_sig_failures=$(echo "$output" \
    | grep 'failed:' \
    | grep -cv 'require-image-signature' \
    || true)

  if [ "$non_sig_failures" -eq 0 ]; then
    pass "$name — passes all pod security/RBAC policies (image sig check skipped offline)"
  else
    fail "$name — has non-signature policy violations:"
    echo "$output" | grep 'failed:' | grep -v 'require-image-signature' | head -5 | sed 's/^/      /' || true
    FAILED=$((FAILED + 1))
  fi
}

# ─── Test cases ───────────────────────────────────────────────────────────
info "Kyverno admission policy tests (kyverno-cli via Docker)"
echo ""

#  Signature / pod security policies.
#  Note: the "good" pod uses run_compliant_pod_test which verifies
#  all pod security rules pass. Image signature verification is skipped
#  offline (requires a real signed image + registry access).
run_compliant_pod_test   "compliant-pod-passes-security"   "good-pod.yaml"
run_kyverno_test         "privileged-pod-blocked"          "fail" "bad-privileged-pod.yaml"
run_kyverno_test         "root-user-pod-blocked"           "fail" "bad-root-user.yaml"
run_kyverno_test         "default-sa-blocked"              "fail" "bad-default-sa.yaml"
run_kyverno_test         "automount-sa-token-blocked"      "fail" "bad-automount-sa.yaml"
run_kyverno_test         "writable-rootfs-pod-blocked"     "fail" "bad-writable-rootfs.yaml"

echo ""

# ─── Summary ─────────────────────────────────────────────────────────────
if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}=== All Kyverno policy tests passed ===${NC}"
  exit 0
else
  echo -e "${RED}=== $FAILED policy test(s) failed ===${NC}"
  exit 1
fi
