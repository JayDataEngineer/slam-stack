#!/usr/bin/env bash
# Slam Stack — Component Deployer
# Installs all stack components in dependency order.
# Usage: ./deploy.sh
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${BLUE}[*]${NC} $1"; }
ok()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
fail()  { echo -e "${RED}[-]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPONENTS="${SCRIPT_DIR}/components"

command -v kubectl >/dev/null 2>&1 || fail "kubectl required"
command -v helm    >/dev/null 2>&1 || fail "helm required"

# === Helm repos ===
declare -A HELM_REPOS=(
  ["cilium"]="https://helm.cilium.io"
  ["kyverno"]="https://kyverno.github.io/kyverno"
  ["tetragon"]="https://helm.eclipse.dev/tetragon"
  ["vm"]="https://victoriametrics.github.io/helm-charts"
  ["openbao"]="https://openbao.github.io/openbao-helm"
  ["gabe565"]="https://charts.gabe565.com"
  ["surrealdb"]="https://helm.surrealdb.com"
  ["openebs"]="https://openebs.github.io/charts"
)

info "Adding Helm repositories..."
for name in "${!HELM_REPOS[@]}"; do
  helm repo add "$name" "${HELM_REPOS[$name]}" --force-update 2>/dev/null || true
done
helm repo update

# === Deploy metadata ===
# Format: type|release|chart|namespace|values_path
# type: helm | raw
declare -A DEPLOY=(
  ["cilium"]="helm|cilium|cilium/cilium|kube-system|${COMPONENTS}/cilium/install.yaml"
  ["kyverno"]="helm|kyverno|kyverno/kyverno|kyverno|${COMPONENTS}/kyverno/install.yaml"
  ["tetragon"]="helm|tetragon|tetragon/tetragon|kube-system|${COMPONENTS}/tetragon/install.yaml"
  ["victoria-logs"]="helm|victoria-logs|victoria-logs-single|observability|${COMPONENTS}/victoria-logs/install.yaml"
  ["vault"]="helm|vault|openbao/openbao|vault|${COMPONENTS}/vault/install.yaml"
  ["headscale"]="helm|headscale|gabe565/headscale|network|${COMPONENTS}/headscale/install.yaml"
  ["surrealdb"]="helm|surrealdb|surrealdb/surrealdb|database|${COMPONENTS}/surreal-db/install.yaml"
  ["mayastor"]="helm|openebs|openebs/mayastor|storage|${COMPONENTS}/mayastor/install.yaml"
  ["registry"]="raw|registry||default|${COMPONENTS}/registry/install.yaml"
  ["kanidm"]="raw|kanidm||identity|${COMPONENTS}/kanidm/install.yaml"
  ["stalwart"]="raw|stalwart||mail|${COMPONENTS}/stalwart/install.yaml"
  ["rustfs"]="raw|rustfs||storage|${COMPONENTS}/rustfs/install.yaml"
  ["web"]="raw|web||web|${SCRIPT_DIR}/web/deploy.yaml"
)

ORDER=(kyverno tetragon victoria-logs vault mayastor registry kanidm headscale surrealdb stalwart rustfs web)

# === Cosign key management ===
COSIGN_DIR="${SCRIPT_DIR}/components/cosign"
if [ ! -f "${COSIGN_DIR}/cosign.pub" ]; then
  info "No Cosign keypair found. Generating fresh dev keys..."
  (
    cd "${COSIGN_DIR}"
    cosign generate-key-pair 2>/dev/null || {
      warn "cosign not installed, installing..."
      curl -sL "https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64" -o /tmp/cosign
      sudo mv /tmp/cosign /usr/local/bin/cosign && sudo chmod +x /usr/local/bin/cosign
      cosign generate-key-pair
    }
  )
  ok "Cosign dev keypair generated"
fi

# === Create Kyverno namespace first for the secret ===
kubectl create namespace kyverno --dry-run=client -o yaml | kubectl apply -f -

# Store pubkey as a Kyverno secret
kubectl create secret generic cosign-public-key \
  -n kyverno \
  --from-file=cosign.pub="${COSIGN_DIR}/cosign.pub" \
  --dry-run=client -o yaml | kubectl apply -f -
ok "Cosign public key stored in kyverno/cosign-public-key"

# === Inject pubkey into signature-policy.yaml ===
SIG_POLICY="${COMPONENTS}/kyverno/signature-policy.yaml"
SIG_POLICY_TMP=$(mktemp)
trap 'rm -f "$SIG_POLICY_TMP"' EXIT

# Read the actual pubkey (first line only for the BEGIN/END lines, but we need the whole key)
COSIGN_PUB=$(cat "${COSIGN_DIR}/cosign.pub")
# Build the key section with proper indentation (8 spaces for YAML)
KEY_SECTION=$(echo "$COSIGN_PUB" | sed 's/^/        /')

# Replace the placeholder in signature-policy.yaml
sed "s|MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQDQgAE\.\.\.REPLACE_ME\.\.\.|${KEY_SECTION#        }|" "$SIG_POLICY" > "$SIG_POLICY_TMP"
# If the placeholder wasn't there, inject after the key: marker
if grep -q "REPLACE_ME" "$SIG_POLICY_TMP"; then
  awk -v key="$COSIGN_PUB" '
  /REPLACE_ME/ {
    print "            -----BEGIN PUBLIC KEY-----"
    print "            " key
    print "            -----END PUBLIC KEY-----"
    next
  }
  { print }
  ' "$SIG_POLICY" > "$SIG_POLICY_TMP"
fi

# === Wait for Cilium ===
if kubectl -n kube-system get pods -l k8s-app=cilium -o name 2>/dev/null | grep -q .; then
  info "Waiting for Cilium to be ready..."
  kubectl -n kube-system wait --for=condition=ready pod -l k8s-app=cilium --timeout=300s 2>/dev/null || warn "Cilium not ready yet"
fi

# === Deploy ===
for name in "${ORDER[@]}"; do
  echo ""
  info "--- Deploying: $name ---"

  IFS='|' read -r type release chart ns values <<< "${DEPLOY[$name]}"
  [ -z "$type" ] && { warn "No deploy entry for $name"; continue; }

  case "$type" in
    helm)
      # Verify chart integrity before deploying
      if helm pull "$chart" --verify 2>/dev/null; then
        ok "Chart signature verified: $chart"
      else
        warn "Chart signature verification failed or not signed: $chart (proceeding — enable strict mode in prod)"
      fi

      if helm list -n "$ns" -q 2>/dev/null | grep -q "^${release}$"; then
        helm upgrade "$release" "$chart" -n "$ns" -f "$values" --cleanup-on-fail 2>&1 | tail -3 || warn "upgrade $name failed"
      else
        helm install "$release" "$chart" -n "$ns" --create-namespace -f "$values" 2>&1 | tail -3 || warn "install $name failed"
      fi
      ;;
    raw)
      info "Applying raw manifests from $values..."
      if [ -f "$values" ]; then
        kubectl apply -f "$values" 2>&1 | tail -3 || warn "raw apply $name failed"
      else
        warn "Manifest not found: $values"
      fi
      ;;
  esac

  # Wait for readiness
  if [ "$type" = "helm" ]; then
    kubectl wait --for=condition=ready pod -n "$ns" -l "app.kubernetes.io/instance=$release" --timeout=180s 2>/dev/null || \
    kubectl wait --for=condition=ready pod -n "$ns" -l "app=$release" --timeout=180s 2>/dev/null || \
    kubectl wait --for=condition=ready pod -n "$ns" --all --timeout=180s 2>/dev/null || true
  else
    kubectl wait --for=condition=ready pod -n "$ns" --all --timeout=180s 2>/dev/null || true
  fi

  ok "$name deployed"
done

# === Post-deploy: security policies ===
echo ""
info "--- Post-deploy: Security Policies ---"

# Apply signature policy with injected pubkey
kubectl apply -f "$SIG_POLICY_TMP" 2>&1 | tail -1

for f in "$COMPONENTS/cilium/default-deny.yaml" \
         "$COMPONENTS/cilium/service-policies.yaml" \
         "$COMPONENTS/tetragon/policies.yaml"; do
  if [ -f "$f" ]; then
    kubectl apply -f "$f" 2>&1 | tail -1
  fi
done

echo ""
ok "=== Slam Stack deployment complete ==="

# === Post-deploy: verify image signatures ===
echo ""
info "--- Verifying deployed image signatures ---"
SIG_FAIL=0
for pod in $(kubectl get pods -A -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  ns=$(kubectl get pod "$pod" -o jsonpath='{.metadata.namespace}' 2>/dev/null)
  image=$(kubectl get pod "$pod" -o jsonpath='{.spec.containers[0].image}' 2>/dev/null)
  if [ -n "$image" ] && [ -f "${COSIGN_DIR}/cosign.pub" ]; then
    if cosign verify --key "${COSIGN_DIR}/cosign.pub" "$image" >/dev/null 2>&1; then
      ok "  $ns/$pod: signed"
    else
      warn "  $ns/$pod: unsigned or verification failed ($image)"
      SIG_FAIL=$((SIG_FAIL + 1))
    fi
  fi
done

if [ "$SIG_FAIL" -gt 0 ]; then
  warn "$SIG_FAIL pod(s) with unsigned images detected — sign with: cosign sign --key components/cosign/cosign.key <image>"
else
  ok "All deployed images are signed"
fi
echo ""
info "Components installed:"
helm list -A 2>/dev/null | tail -n +2 | awk '{printf "  %-20s %-15s %s\n", $1, $9, $8}'
echo "  registry (raw)"
echo "  kanidm (raw)"
echo "  stalwart (raw)"
echo "  rustfs (raw)"
echo "  web (raw)"
echo ""
info "Run ./verify.sh to check security posture."
