#!/usr/bin/env bash
# Slam Stack — Component Deployer
# Installs all stack components in dependency order.
# Supports both Helm charts and raw K8s manifests.
# Usage: ./deploy.sh [--dev|--prod]
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${BLUE}[*]${NC} $1"; }
ok()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
fail()  { echo -e "${RED}[-]${NC} $1"; exit 1; }

MODE="${1:---dev}"
COMPONENTS="$(cd "$(dirname "$0")" && pwd)/components"

command -v kubectl >/dev/null 2>&1 || fail "kubectl required"
command -v helm    >/dev/null 2>&1 || fail "helm required"

# === Helm repos that actually exist ===
declare -A HELM_REPOS=(
  ["cilium"]="https://helm.cilium.io"
  ["kyverno"]="https://kyverno.github.io/kyverno"
  ["vm"]="https://victoriametrics.github.io/helm-charts"
  ["openbao"]="https://openbao.github.io/openbao-helm"
  ["gabe565"]="https://charts.gabe565.com"
  ["surrealdb"]="https://helm.surrealdb.com"
)

info "Adding Helm repositories..."
for name in "${!HELM_REPOS[@]}"; do
  helm repo add "$name" "${HELM_REPOS[$name]}" --force-update 2>/dev/null || true
done
helm repo update

# === Deploy order with metadata ===
# type: helm | raw | raw-apply
# For helm: "helm name, repo, chart, namespace, values.yaml"
# For raw: "path/to/manifests, namespace"
declare -A DEPLOY=(
  ["cilium"]="helm|cilium|cilium/cilium|kube-system|${COMPONENTS}/cilium/install.yaml"
  ["kyverno"]="helm|kyverno|kyverno/kyverno|kyverno|${COMPONENTS}/kyverno/install.yaml"
  ["tetragon"]="helm|tetragon|tetragon/tetragon|kube-system|${COMPONENTS}/tetragon/install.yaml"
  ["victoria-logs"]="helm|victoria-logs|victoria-logs-single|observability|${COMPONENTS}/victoria-logs/install.yaml"
  ["vault"]="helm|vault|openbao/openbao|vault|${COMPONENTS}/vault/install.yaml"
  ["headscale"]="helm|headscale|gabe565/headscale|network|${COMPONENTS}/headscale/install.yaml"
  ["surrealdb"]="helm|surrealdb|surrealdb/surrealdb|database|${COMPONENTS}/surreal-db/install.yaml"
  ["kanidm"]="raw|kanidm|identity|${COMPONENTS}/kanidm/install.yaml"
  ["stalwart"]="raw|stalwart|mail|${COMPONENTS}/stalwart/install.yaml"
  ["rustfs"]="raw|rustfs|storage|${COMPONENTS}/rustfs/install.yaml"
)

ORDER=(cilium kyverno tetragon victoria-logs vault kanidm headscale surrealdb stalwart rustfs)

# === Wait for Cilium ===
if kubectl -n kube-system get pods -l k8s-app=cilium -o name 2>/dev/null | grep -q .; then
  info "Waiting for Cilium to be ready..."
  kubectl -n kube-system wait --for=condition=ready pod -l k8s-app=cilium --timeout=300s 2>/dev/null || warn "Cilium not ready yet"
fi

# === Deploy ===
for name in "${ORDER[@]}"; do
  echo ""
  info "--- Deploying: $name ---"

  IFS='|' read -rtype chart_name ns values <<< "${DEPLOY[$name]}"

  case "$type" in
    helm)
      INSTALLED=$(helm list -n "$ns" -q 2>/dev/null | grep -c "^$chart_name$" || true)
      if [ "$INSTALLED" -gt 0 ]; then
        helm upgrade "$chart_name" "$chart_name" -n "$ns" -f "$values" --cleanup-on-fail 2>&1 | tail -3 || warn "upgrade failed"
      else
        helm install "$chart_name" "$chart_name" -n "$ns" --create-namespace -f "$values" 2>&1 | tail -3 || warn "install failed"
      fi
      ;;
    raw)
      info "Applying raw manifests from $values..."
      kubectl apply -f "$values" 2>&1 | tail -3 || warn "raw apply failed"
      ;;
  esac

  # Wait for readiness
  if [ "$type" = "helm" ]; then
    kubectl wait --for=condition=ready pod -n "$ns" -l "app.kubernetes.io/instance=$chart_name" --timeout=180s 2>/dev/null || \
    kubectl wait --for=condition=ready pod -n "$ns" -l "app=$chart_name" --timeout=180s 2>/dev/null || \
    kubectl wait --for=condition=ready pod -n "$ns" --all --timeout=180s 2>/dev/null || true
  else
    kubectl wait --for=condition=ready pod -n "$ns" -l "app=$chart_name" --timeout=180s 2>/dev/null || true
  fi

  ok "$name deployed"
done

# === Post-deploy: policies ===
echo ""
info "--- Post-deploy: Security Policies ---"

for f in "$COMPONENTS/cilium/default-deny.yaml" \
         "$COMPONENTS/cilium/service-policies.yaml" \
         "$COMPONENTS/kyverno/signature-policy.yaml" \
         "$COMPONENTS/tetragon/policies.yaml"; do
  if [ -f "$f" ]; then
    kubectl apply -f "$f" 2>&1 | tail -1
  fi
done

echo ""
ok "=== Slam Stack deployment complete ==="
echo ""
info "Components installed:"
helm list -A 2>/dev/null | tail -n +2 | awk '{printf "  %-20s %-15s %s\n", $1, $9, $8}'
echo "  kanidm (raw)"
echo "  stalwart (raw)"
echo "  rustfs (raw)"
echo ""
info "Run ./verify.sh to check security posture."
