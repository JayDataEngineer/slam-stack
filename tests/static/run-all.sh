#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Static analysis: shellcheck + yamllint + kubeconform.
# All tools run via Docker — no host installs required.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SHELLCHECK_IMAGE="${SHELLCHECK_IMAGE:-koalaman/shellcheck:stable}"
YAMLLINT_IMAGE="${YAMLLINT_IMAGE:-pipelinecomponents/yamllint:latest}"
KUBECONFORM_IMAGE="${KUBECONFORM_IMAGE:-ghcr.io/yannh/kubeconform:latest}"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${BLUE}[*]${NC} $1"; }
pass() { echo -e "  ${GREEN}PASS${NC} $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; }

FAILED=0

# ─── shellcheck ──────────────────────────────────────────────────────────
info "shellcheck on all .sh files"
mapfile -t SHELL_FILES < <(find "$REPO_ROOT" \
  -name '*.sh' -type f \
  -not -path '*/.git/*' \
  -not -path '*/target/*' \
  -not -path '*/node_modules/*' \
  -not -path '*/.flatcar/*' \
  -not -path '*/.vm/*' \
  -not -name '*.bundle' \
  | sort)

if [ "${#SHELL_FILES[@]}" -eq 0 ]; then
  fail "No shell scripts found"
  FAILED=$((FAILED + 1))
else
  # Pull image quietly first so Docker progress doesn't pollute the output.
  docker pull "$SHELLCHECK_IMAGE" >/dev/null 2>&1 || true

  # Strip the repo root so Docker paths are relative.
  REL_FILES=()
  for f in "${SHELL_FILES[@]}"; do
    REL_FILES+=("${f#"$REPO_ROOT"/}")
  done
  # Capture stderr separately (Docker noise) — only shellcheck output on stdout.
  OUTPUT=$(docker run --rm -v "$REPO_ROOT:/work" -w /work \
    "$SHELLCHECK_IMAGE" \
    --format=gcc --color=never --exclude=SC1090,SC1091,SC2155 \
    "${REL_FILES[@]}" 2>/dev/null || true)
  if [ -z "$OUTPUT" ]; then
    pass "${#SHELL_FILES[@]} shell scripts clean"
  else
    fail "shellcheck found issues in ${#SHELL_FILES[@]} scripts:"
    echo "$OUTPUT" | head -40 | sed 's/^/    /'
    FAILED=$((FAILED + 1))
  fi
fi
echo ""

# ─── yamllint ────────────────────────────────────────────────────────────
info "yamllint on all YAML files"
YAML_COUNT=$(find "$REPO_ROOT" \
  -not -path '*/.git/*' -not -path '*/target/*' \
  -not -path '*/node_modules/*' -not -path '*/.flatcar/*' \
  -not -path '*/.vm/*' -not -path '*/.terraform/*' \
  -type f \( -name '*.yaml' -o -name '*.yml' \) | wc -l)

docker pull "$YAMLLINT_IMAGE" >/dev/null 2>&1 || true
OUTPUT=$(docker run --rm -v "$REPO_ROOT:/work" -w /work \
  "$YAMLLINT_IMAGE" \
  yamllint -d "{extends: default, rules: {line-length: disable, document-start: disable, indentation: {indent-sequences: consistent}, trailing-spaces: disable, comments-indentation: disable, comments: {require-starting-space: true, ignore-shebangs: true}}" \
  /work 2>/dev/null || true)
ERRORS=$(echo "$OUTPUT" | grep -c ': error:' || true)
WARNINGS=$(echo "$OUTPUT" | grep -c ': warning:' || true)
if [ "$ERRORS" -eq 0 ]; then
  pass "$YAML_COUNT YAML files clean ($WARNINGS warnings)"
else
  fail "yamllint found $ERRORS errors:"
  echo "$OUTPUT" | grep ': error:' | head -15 | sed 's/^/    /'
  FAILED=$((FAILED + 1))
fi
echo ""

# ─── kubeconform ─────────────────────────────────────────────────────────
info "kubeconform on kustomize-built manifests (all cluster overlays + phases)"

KUBECONFORM_OPTS=(-summary -ignore-missing-schemas -skip ReplicationController
  -schema-location 'https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone/{resourceKind}.json')

validate_dir() {
  local label="$1"
  local dir="$2"
  local tmpfile
  tmpfile=$(mktemp /tmp/slam-kubeconform-XXXXXX.yaml)

  if ! kubectl kustomize "$dir" > "$tmpfile" 2>/dev/null; then
    fail "$label — kustomize build failed"
    rm -f "$tmpfile"
    FAILED=$((FAILED + 1))
    return
  fi

  local count
  count=$(grep -c '^kind:' "$tmpfile" || echo 0)
  if [ "$count" -eq 0 ]; then
    pass "$label — (no manifests)"
    rm -f "$tmpfile"
    return
  fi

  local output
  docker pull "$KUBECONFORM_IMAGE" >/dev/null 2>&1 || true
  output=$(docker run --rm -v "$tmpfile:/manifests.yaml:ro" \
    "$KUBECONFORM_IMAGE" \
    "${KUBECONFORM_OPTS[@]}" /manifests.yaml 2>/dev/null || true)
  rm -f "$tmpfile"

  # kubeconform output: "Summary: N resources found ... - Valid: X, Invalid: Y, Errors: Z, Skipped: W"
  # A pass means Invalid: 0 and Errors: 0.
  local invalid errors
  invalid=$(echo "$output" | grep -oP 'Invalid: \K[0-9]+' || echo "0")
  errors=$(echo "$output" | grep -oP 'Errors: \K[0-9]+' || echo "0")

  if [ "$invalid" -eq 0 ] && [ "$errors" -eq 0 ]; then
    pass "$label — $count manifests valid"
  else
    fail "$label — kubeconform found $invalid invalid, $errors errors:"
    echo "$output" | grep -v '^Summary:' | head -10 | sed 's/^/    /'
    FAILED=$((FAILED + 1))
  fi
}

# Validate every cluster overlay.
for flavor in minimal core og matrix commet rust; do
  [ -d "$REPO_ROOT/clusters/$flavor" ] && validate_dir "clusters/$flavor" "$REPO_ROOT/clusters/$flavor"
done

# Validate every phase directory.
for phase_dir in "$REPO_ROOT"/clusters/phases/*/; do
  [ -d "$phase_dir" ] && validate_dir "phases/$(basename "$phase_dir")" "$phase_dir"
done
for phase_dir in "$REPO_ROOT"/clusters/minimal/phases/*/; do
  [ -d "$phase_dir" ] && validate_dir "minimal/phases/$(basename "$phase_dir")" "$phase_dir"
done

# Validate standalone component kustomizations.
for comp_dir in "$REPO_ROOT"/components/*/; do
  comp_name=$(basename "$comp_dir")
  # Skip if no kustomization.yaml.
  [ -f "$comp_dir/kustomization.yaml" ] || continue
  # Skip the root components/ kustomization (just a aggregator).
  [ "$comp_name" = "kustomization.yaml" ] && continue
  validate_dir "components/$comp_name" "$comp_dir"
done

# Validate workload manifests.
for wl_dir in "$REPO_ROOT"/workloads/*/manifests/; do
  [ -d "$wl_dir" ] && validate_dir "workloads/$(basename "$(dirname "$wl_dir")")" "$wl_dir"
done

echo ""

# ─── Summary ─────────────────────────────────────────────────────────────
if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}=== All static analysis checks passed ===${NC}"
  exit 0
else
  echo -e "${RED}=== $FAILED check(s) failed ===${NC}"
  exit 1
fi
