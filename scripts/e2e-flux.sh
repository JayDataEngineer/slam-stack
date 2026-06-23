#!/usr/bin/env bash
# Slam Stack — Flux Pipeline E2E Validation
# Validates the entire Flux pipeline from repo state, no cluster needed.
# Checks: kustomize builds, HelmRelease completeness, secret hygiene,
# dependency ordering, source references, and policy coverage.
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
pass() { echo -e "  ${GREEN}PASS${NC} $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; FAILED=$((FAILED + 1)); }
info() { echo -e "${BLUE}[*]${NC} $1"; }
warn() { echo -e "  ${YELLOW}WARN${NC} $1"; }

FAILED=0
FLAVOR="${FLAVOR:-og}"

echo "=== Slam Stack Flux Pipeline E2E ==="
echo "Flavor: $FLAVOR"
echo ""

# === 1. All kustomize overlays build ===
info "1. Kustomize builds..."
for dir in clusters/phases/00-sources clusters/phases/01-cni clusters/phases/02-core \
           clusters/phases/03-infra clusters/phases/04-services clusters/common \
           clusters/minimal/phases/00-sources clusters/minimal/phases/01-cni \
           clusters/minimal/phases/02-platform clusters/minimal/phases/03-identity \
           clusters/$FLAVOR clusters/base; do
  if kubectl kustomize "$dir" > /dev/null 2>&1; then
    count=$(kubectl kustomize "$dir" 2>/dev/null | grep -c '^kind:')
    pass "$dir ($count resources)"
  else
    fail "$dir — build failed"
    kubectl kustomize "$dir" 2>&1 | tail -3
  fi
done
echo ""

# === 2. Cluster overlay outputs only Kustomization CRDs ===
info "2. Cluster overlay purity (only Flux Kustomization CRDs)..."
for flavor in og matrix commet rust minimal core; do
  non_kust=$(kubectl kustomize "clusters/$flavor" 2>/dev/null | grep '^kind:' | grep -cv 'Kustomization' || true)
  if [ "$non_kust" -eq 0 ]; then
    pass "clusters/$flavor — only Kustomization CRDs"
  else
    fail "clusters/$flavor — $non_kust non-Kustomization resources found"
  fi
done
echo ""

# === 3. Dependency chain is complete (no broken dependsOn) ===
info "3. Dependency chain integrity..."
for flavor in og matrix commet rust minimal; do
  # Extract CRD names (metadata.name, indented 2 spaces under metadata:)
  crd_names=$(kubectl kustomize "clusters/$flavor" 2>/dev/null | grep -oP '(?<=^  name: )slam-\S+' | sort -u)
  # Extract dependsOn target names (under dependsOn: block, 6-space indent)
  dep_names=$(kubectl kustomize "clusters/$flavor" 2>/dev/null | grep -oP '(?<=- name: )slam-\S+' | sort -u)
  for dep in $dep_names; do
    if echo "$crd_names" | grep -qx "$dep"; then
      pass "$flavor: dependsOn '$dep' resolves"
    else
      fail "$flavor: dependsOn '$dep' — no matching Kustomization CRD"
    fi
  done
  # Check ordering: sources has no dep
  sources_block=$(kubectl kustomize "clusters/$flavor" 2>/dev/null | sed -n '/^  name: slam-sources$/,/^---$/p')
  if echo "$sources_block" | grep -q 'dependsOn'; then
    fail "$flavor: slam-sources should have no dependsOn (root of chain)"
  else
    pass "$flavor: slam-sources is root (no dependsOn)"
  fi
done
echo ""

# === 4. Every HelmRelease references an existing HelmRepository ===
info "4. HelmRelease source references..."
repos=$(grep '  name:' clusters/base/sources/helm-repositories.yaml | awk '{print $2}' | sort -u)
for hr in $(find components -name 'helm-release.yaml' -type f 2>/dev/null); do
  repo=$(grep -A3 'sourceRef:' "$hr" | grep 'name:' | tail -1 | awk '{print $2}')
  comp=$(basename "$(dirname "$hr")")
  if echo "$repos" | grep -qx "$repo"; then
    pass "$comp → HelmRepository '$repo'"
  else
    fail "$comp references missing HelmRepository '$repo'"
  fi
done
echo ""

# === 5. No REPLACE_ME in manifests ===
info "5. Secret hygiene — no placeholder secrets..."
placeholders=$(grep -rn 'REPLACE.ME' --include='*.yaml' components/ flavors/ clusters/ | grep -v deploy.sh | grep -v bootstrap.sh || true)
if [ -z "$placeholders" ]; then
  pass "No REPLACE_ME placeholders in manifests"
else
  fail "Found placeholder secrets:"
  echo "$placeholders"
fi
echo ""

# === 6. Every component directory has kustomization.yaml ===
info "6. Component kustomization coverage..."
for dir in components/*/; do
  name=$(basename "$dir")
  case "$name" in cosign|flux) continue ;; esac  # non-deployable
  if [ -f "$dir/kustomization.yaml" ]; then
    res_count=$(grep -c '^\s*- ' "$dir/kustomization.yaml" 2>/dev/null || echo 0)
    pass "$name ($res_count resources)"
  else
    fail "$name — missing kustomization.yaml"
  fi
done
echo ""

# === 7. All YAML files in component dirs are listed in kustomization.yaml ===
info "7. No orphaned YAML files..."
for dir in components/*/; do
  name=$(basename "$dir")
  [ -f "$dir/kustomization.yaml" ] || continue
  for yaml in "$dir"*.yaml; do
    [ -f "$yaml" ] || continue
    fname=$(basename "$yaml")
    case "$fname" in install.yaml|kustomization.yaml) continue ;; esac
    if grep -q "$fname" "$dir/kustomization.yaml"; then
      : # listed, OK
    else
      warn "$name/$fname not in kustomization.yaml (may be orphaned)"
    fi
  done
done
echo ""

# === 8. Flavor component coverage ===
info "8. Flavor components..."
for flavor_dir in flavors/*/; do
  flavor_name=$(basename "$flavor_dir")
  # core has no deployable components; minimal has an intentionally-empty bundle
  [ "$flavor_name" = "core" ] && continue
  [ -f "$flavor_dir/kustomization.yaml" ] || { fail "$flavor_name — no kustomization.yaml"; continue; }
  # Check each component listed — resolves cross-flavor refs (rust, commet reuse components)
  while IFS= read -r comp_ref; do
    # Resolve absolute path relative to flavors/<name>/
    comp_path="$(cd "$flavor_dir" && realpath -m "$comp_ref" 2>/dev/null)"
    if [ -n "$comp_path" ] && [ -f "$comp_path/kustomization.yaml" ]; then
      pass "$flavor_name/$comp_ref"
    else
      fail "$flavor_name/$comp_ref — missing kustomization.yaml"
    fi
  done < <(grep -oP '^\s*-\s+\K\S*components/\S+' "$flavor_dir/kustomization.yaml" 2>/dev/null || true)
  # Policies dir — only required for non-empty flavors
  if [ -f "$flavor_dir/policies/kustomization.yaml" ]; then
    pass "$flavor_name/policies"
  elif [ "$flavor_name" = "minimal" ]; then
    pass "$flavor_name/policies (skipped: empty flavor)"
  fi
done
echo ""

# === 9. Cosign public key referenced in signature policy ===
info "9. Image signature enforcement..."
if grep -q 'BEGIN PUBLIC KEY' components/kyverno/signature-policy.yaml; then
  # Extract key from policy and compare with cosign.pub
  policy_key=$(sed -n '/BEGIN PUBLIC KEY/,/END PUBLIC KEY/p' components/kyverno/signature-policy.yaml | grep -v 'BEGIN\|END' | tr -d ' \n')
  file_key=$(grep -v 'BEGIN\|END' components/cosign/cosign.pub | tr -d ' \n')
  if [ "$policy_key" = "$file_key" ]; then
    pass "Signature policy key matches cosign.pub"
  else
    fail "Signature policy key differs from cosign.pub"
  fi
else
  fail "No public key in signature policy"
fi
echo ""

# === 10. Phase ordering — verify resource types in correct phase ===
info "10. Phase content validation..."
# Phase 00 should only have HelmRepositories
phase0_kinds=$(kubectl kustomize clusters/phases/00-sources/ 2>/dev/null | grep '^kind:' | sort -u)
if echo "$phase0_kinds" | grep -q 'HelmRepository'; then
  pass "Phase 00 has HelmRepositories"
else
  fail "Phase 00 missing HelmRepositories"
fi

# Phase 01 should have Cilium HelmRelease + policies + RuntimeClass
phase1_kinds=$(kubectl kustomize clusters/phases/01-cni/ 2>/dev/null | grep '^kind:' | sort -u)
for expected in HelmRelease TracingPolicy CiliumNetworkPolicy ClusterPolicy RuntimeClass ServiceAccount; do
  if echo "$phase1_kinds" | grep -q "$expected"; then
    pass "Phase 01 has $expected"
  else
    fail "Phase 01 missing $expected"
  fi
done
echo ""

# === Summary ===
echo "=== Results ==="
if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}All Flux pipeline checks passed.${NC}"
else
  echo -e "${RED}$FAILED check(s) failed.${NC}"
fi
exit $FAILED
