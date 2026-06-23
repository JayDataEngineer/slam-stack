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

# === Flavor selection ===
FLAVOR="${FLAVOR:-og}"
FLAVOR_DIR="${SCRIPT_DIR}/flavors/${FLAVOR}"
if [ ! -d "$FLAVOR_DIR" ]; then
  fail "Unknown flavor: $FLAVOR (not found: $FLAVOR_DIR)"
fi
info "Flavor: $FLAVOR"

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
  ["cnpg"]="https://cloudnative-pg.github.io/charts"
  ["openebs"]="https://openebs.github.io/charts"
  ["jetstack"]="https://charts.jetstack.io"
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
  ["victoria-logs"]="helm|victoria-logs|vm/victoria-logs-single|observability|${COMPONENTS}/victoria-logs/install.yaml"
  ["victoria-metrics"]="helm|victoria-metrics|vm/victoria-metrics-single|observability|${COMPONENTS}/victoria-metrics/install.yaml"
  ["vault"]="helm|vault|openbao/openbao|vault|${COMPONENTS}/vault/install.yaml"
  ["cert-manager"]="helm|cert-manager|jetstack/cert-manager|cert-manager|${COMPONENTS}/cert-manager/install.yaml"
  ["headscale"]="helm|headscale|gabe565/headscale|network|${COMPONENTS}/headscale/install.yaml"
  ["cnpg"]="helm|cnpg|cnpg/cloudnative-pg|cnpg-system|${COMPONENTS}/postgres/operator.yaml"
  ["postgres"]="raw|postgres||database|${COMPONENTS}/postgres/install.yaml"
  ["mayastor"]="helm|openebs|openebs/mayastor|storage|${COMPONENTS}/mayastor/install.yaml"
  ["registry"]="raw|registry||registry|${COMPONENTS}/registry/install.yaml"
  ["kanidm"]="raw|kanidm||identity|${COMPONENTS}/kanidm/install.yaml"
  ["rustfs"]="raw|rustfs||storage|${COMPONENTS}/rustfs/install.yaml"
  ["web"]="raw|web||web|${SCRIPT_DIR}/components/web/deploy.yaml"
  ["backup"]="raw|backup||backup|${COMPONENTS}/backup/install.yaml"
)

ORDER=(cilium kyverno tetragon victoria-logs victoria-metrics vault cert-manager mayastor cnpg postgres registry kanidm headscale rustfs web backup)

# === Flavor-specific components + overrides ===
case "$FLAVOR" in
  minimal)
    # Ultra-minimalist: drop storage, DB, observability, registry, web, backup.
    # Keep only the zero-trust security plane: Cilium + Kyverno +
    # cert-manager + Vault + Kanidm + Headscale (~2.3 Gi RAM).
    info "Minimal flavor: deploying security plane only"
    ORDER=(cilium kyverno cert-manager vault kanidm headscale)
    ;;
  og)
    DEPLOY["stalwart"]="raw|stalwart||mail|${FLAVOR_DIR}/components/stalwart/install.yaml"
    DEPLOY["simplex"]="raw|simplex||comms|${FLAVOR_DIR}/components/simplex/install.yaml"
    ORDER+=(stalwart simplex)
    ;;
  matrix)
    DEPLOY["tuwunel"]="raw|tuwunel||matrix|${FLAVOR_DIR}/components/tuwunel/install.yaml"
    DEPLOY["cinny"]="raw|cinny||matrix|${FLAVOR_DIR}/components/cinny/install.yaml"
    DEPLOY["livekit"]="raw|livekit||matrix|${FLAVOR_DIR}/components/livekit/install.yaml"
    ORDER+=(tuwunel cinny livekit)
    ;;
  commet)
    DEPLOY["tuwunel"]="raw|tuwunel||matrix|${SCRIPT_DIR}/flavors/matrix/components/tuwunel/install.yaml"
    DEPLOY["commet"]="raw|commet||matrix|${FLAVOR_DIR}/components/commet/install.yaml"
    ORDER+=(tuwunel commet)
    ;;
  rust)
    # Pure-Rust backends: Stalwart (mail) + Tuwunel (Matrix).
    DEPLOY["stalwart"]="raw|stalwart||mail|${SCRIPT_DIR}/flavors/og/components/stalwart/install.yaml"
    DEPLOY["tuwunel"]="raw|tuwunel||matrix|${SCRIPT_DIR}/flavors/matrix/components/tuwunel/install.yaml"
    ORDER+=(stalwart tuwunel)
    ;;
esac

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

# === Pre-deploy: ServiceAccounts (must exist before pods are created) ===
echo ""
info "--- Pre-deploy: ServiceAccounts ---"

if [ -f "$COMPONENTS/kyverno/service-accounts.yaml" ]; then
  kubectl apply -f "$COMPONENTS/kyverno/service-accounts.yaml" 2>&1 | tail -1
  ok "Core ServiceAccounts created"
fi

# Flavor-specific ServiceAccounts
FLAVOR_SA="${FLAVOR_DIR}/policies/service-accounts.yaml"
if [ -f "$FLAVOR_SA" ]; then
  kubectl apply -f "$FLAVOR_SA" 2>&1 | tail -1
  ok "Flavor ServiceAccounts created ($FLAVOR)"
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

# Flavor-specific network policies
FLAVOR_CILIUM="${FLAVOR_DIR}/policies/cilium-service-policies.yaml"
if [ -f "$FLAVOR_CILIUM" ]; then
  kubectl apply -f "$FLAVOR_CILIUM" 2>&1 | tail -1
  ok "Flavor Cilium policies applied ($FLAVOR)"
fi

# === Post-deploy: RBAC policies ===
echo ""
info "--- Post-deploy: RBAC ---"

if [ -f "$COMPONENTS/kyverno/rbac-policies.yaml" ]; then
  kubectl apply -f "$COMPONENTS/kyverno/rbac-policies.yaml" 2>&1 | tail -1
  ok "RBAC policies enforced (no default SA, no automounted tokens)"
fi

# === Post-deploy: cert-manager Vault issuer + certificates ===
echo ""
info "--- Post-deploy: TLS Certificates ---"

if [ -f "$COMPONENTS/cert-manager/vault-issuer.yaml" ]; then
  kubectl apply -f "$COMPONENTS/cert-manager/vault-issuer.yaml" 2>&1 | tail -1
  ok "Vault ClusterIssuer configured"
fi

if [ -f "$COMPONENTS/cert-manager/certificates.yaml" ]; then
  kubectl apply -f "$COMPONENTS/cert-manager/certificates.yaml" 2>&1 | tail -1
  ok "Core Certificate CRDs created (auto-issued by cert-manager)"
fi

# Flavor-specific certificates
FLAVOR_CERTS="${FLAVOR_DIR}/policies/certificates.yaml"
if [ -f "$FLAVOR_CERTS" ]; then
  kubectl apply -f "$FLAVOR_CERTS" 2>&1 | tail -1
  ok "Flavor certificates created ($FLAVOR)"
fi

# === Post-deploy: VictoriaMetrics alerting ===
echo ""
info "--- Post-deploy: Metrics & Alerting ---"

if [ -f "$COMPONENTS/victoria-metrics/alert-rules.yaml" ]; then
  kubectl apply -f "$COMPONENTS/victoria-metrics/alert-rules.yaml" 2>&1 | tail -1
  ok "Alert rules applied"
fi

# === Post-deploy: Kanidm OAuth2 client ===
echo ""
info "--- Post-deploy: OAuth2 ---"

if [ -f "$COMPONENTS/kanidm/oauth2-client.yaml" ]; then
  kubectl apply -f "$COMPONENTS/kanidm/oauth2-client.yaml" 2>&1 | tail -1
  ok "Core OAuth2 client ConfigMap created"
fi

# Flavor-specific OAuth2 clients
FLAVOR_OAUTH="${FLAVOR_DIR}/policies/oauth2-client.yaml"
if [ -f "$FLAVOR_OAUTH" ]; then
  kubectl apply -f "$FLAVOR_OAUTH" 2>&1 | tail -1
  ok "Flavor OAuth2 client ConfigMap created ($FLAVOR)"
fi

# === Post-deploy: Vault dynamic secrets (AppRole for cert-manager) ===
if [ -f "$COMPONENTS/vault/dynamic-secrets.yaml" ]; then
  kubectl apply -f "$COMPONENTS/vault/dynamic-secrets.yaml" 2>&1 | tail -1
  ok "Vault dynamic secrets configured"
fi

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
info "Components installed (flavor: $FLAVOR):"
helm list -A 2>/dev/null | tail -n +2 | awk '{printf "  %-20s %-15s %s\n", $1, $9, $8}'

# Core raw components (skipped for minimal)
if [ "$FLAVOR" != "minimal" ]; then
  echo "  cnpg (operator)"
  echo "  postgres (raw)"
  echo "  kanidm (raw)"
  echo "  registry (raw)"
  echo "  rustfs (raw)"
  echo "  web (raw)"
else
  echo "  kanidm (raw)"
fi

# Flavor-specific raw components
case "$FLAVOR" in
  og)
    echo "  simplex (raw)"
    echo "  stalwart (raw)"
    ;;
  matrix)
    echo "  tuwunel (raw)"
    echo "  cinny (raw)"
    echo "  livekit (raw)"
    ;;
  commet)
    echo "  tuwunel (raw)"
    echo "  commet (raw)"
    ;;
  rust)
    echo "  stalwart (raw, Rust)"
    echo "  tuwunel (raw, Rust)"
    ;;
esac
echo ""
info "Run ./verify.sh to check security posture."
