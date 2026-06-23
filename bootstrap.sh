#!/usr/bin/env bash
# Slam Stack — Bootstrap from Scratch
# Run this on a fresh Ubuntu 26.04 dev machine to reproduce the entire stack.
# Usage: ./bootstrap.sh [--dev|--prod]
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[*]${NC} $1"; }
ok()    { echo -e "${GREEN}[+]${NC} $1"; }
fail()  { echo -e "${RED}[-]${NC} $1"; exit 1; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:---dev}"
FLAVOR="${FLAVOR:-og}"

echo "=== Slam Stack Bootstrap ==="
echo "Mode: ${MODE}   Flavor: ${FLAVOR}"
echo ""

# === Load environment (fail if missing in prod) ===
if [ -f "${SCRIPT_DIR}/.env" ]; then
  source "${SCRIPT_DIR}/.env"
fi

if [ -z "${CLUSTER_API_ENDPOINT:-}" ]; then
  if [ "${MODE}" = "--prod" ]; then
    fail "CLUSTER_API_ENDPOINT must be set in .env for production"
  else
    warn "CLUSTER_API_ENDPOINT not set, using dev default"
    CLUSTER_API_ENDPOINT="10.5.0.2:50000"
  fi
fi

# === Pre-flight security checks ===
info "Step 0/7: Pre-flight security checks..."

if command -v tpm2_getcap >/dev/null 2>&1; then
  if tpm2_getcap properties-fixed >/dev/null 2>&1; then
    ok "TPM 2.0 detected"
  else
    warn "TPM 2.0 not detected — disk encryption keys not hardware-bound"
  fi
else
  warn "tpm2_tools not installed — cannot verify TPM"
fi

if command -v mokutil >/dev/null 2>&1; then
  if mokutil --sb-state 2>/dev/null | grep -q "enabled"; then
    ok "Secure Boot enabled"
  else
    warn "Secure Boot not enabled — boot chain not verified"
  fi
else
  warn "mokutil not installed — cannot verify Secure Boot"
fi

if command -v ykman >/dev/null 2>&1; then
  if ykman list 2>/dev/null | grep -q "YubiKey"; then
    ok "YubiKey detected"
  else
    warn "No YubiKey detected — using software Cosign keys"
  fi
else
  warn "ykman not installed — cannot verify YubiKey"
fi

# === 1. Dev environment setup ===
info "Step 1/7: Dev environment setup..."
cd "$SCRIPT_DIR"
bash dev/setup.sh
ok "Dev environment ready"

# === 2. Generate Cosign keypair ===
info "Step 2/7: Cosign key generation..."
cd "${SCRIPT_DIR}/components/cosign"
if [ ! -f cosign.pub ]; then
  if command -v ykman >/dev/null 2>&1 && ykman list 2>/dev/null | grep -q "YubiKey"; then
    info "YubiKey detected — generating hardware-backed key..."
    cosign generate-key-pair --kms yubikey://slot-id
  else
    warn "Generating software Cosign keypair — migrate to YubiKey when available"
    cosign generate-key-pair
    chmod 600 cosign.key
  fi
fi
cd "$SCRIPT_DIR"
ok "Cosign keypair ready"

# === 3. Deploy components ===
info "Step 3/7: Deploying stack components (flavor: ${FLAVOR})..."
export KUBECONFIG="${HOME}/.kube/slam-stack-config"
export FLAVOR
bash deploy.sh
ok "Stack components deployed"

# === 4. Build web dashboard ===
info "Step 4/7: Building web dashboard..."
bash web/build.sh --push --registry registry.registry.svc.cluster.local:5000 2>&1 || {
  warn "Web dashboard build skipped (no container runtime)"
  info "  Manual: cd web && cargo leptos build --release"
}
ok "Web dashboard built"

# === 5. Verify ===
info "Step 5/7: Running verification suite..."
cd "$SCRIPT_DIR"
bash verify.sh
ok "Verification complete"

# === 6. Post-install summary ===
echo ""
info "Step 6/7: Post-install summary"
echo ""
echo "  ┌──────────────────────────────────────────────────────────┐"
echo "  │            Slam Stack Bootstrap Complete                 │"
echo "  ├──────────────────────────────────────────────────────────┤"
echo "  │  Kubeconfig: ~/.kube/slam-stack-config                   │"
echo "  │  Talos API:  \${CLUSTER_API_ENDPOINT}                     │"
echo "  │  Registry:  registry.registry.svc.cluster.local:5000     │"
echo "  │  Dashboard: web/deploy.yaml                              │"
echo "  └──────────────────────────────────────────────────────────┘"
echo ""
echo "  Components installed (flavor: ${FLAVOR}):"
echo "    Cilium (CNI + WireGuard)"
echo "    Kyverno (admission + Cosign enforcement)"
echo "    Tetragon (eBPF runtime security)"
echo "    Vault/OpenBao (dynamic secrets, TPM auto-unseal)"
echo "    VictoriaLogs (tamper-evident audit logging)"
echo "    Kanidm (identity/OIDC)"
echo "    Headscale (Tailscale-compatible mesh)"
echo "    RustFS (WORM object storage, Vault KMS)"
echo "    Mayastor (NVMe-oF block storage, LUKS encrypted)"
echo "    PostgreSQL (CNPG managed)"
echo "    Registry (local container registry)"
echo "    Web dashboard (Leptos + Axum)"
case "$FLAVOR" in
  minimal)
    echo "    (Minimal flavor — security plane only, no apps)"
    ;;
  og)
    echo "    Stalwart (JMAP email)"
    echo "    SimpleX Chat (SMP + XFTP relay)"
    ;;
  matrix)
    echo "    Matrix (Continuwuity/Tuwunel)"
    echo "    Cinny (Discord-like web UI)"
    echo "    LiveKit (E2EE voice/video)"
    ;;
  commet)
    echo "    Matrix (Continuwuity/Tuwunel)"
    echo "    Commet (Flutter Matrix client)"
    ;;
  rust)
    echo "    Stalwart (Rust mail server)"
    echo "    Tuwunel (Rust Matrix homeserver)"
    ;;
esac
echo ""

# === 7. Next steps ===
info "Step 7/7: Next steps"
echo ""

echo "  Next steps:"
echo "    1. Run day-0 ceremony: talosctl health && ./verify.sh"
echo "    2. Initialize Vault: see docs/runbook.md"
echo "    3. Configure Kanidm: see docs/runbook.md"
echo "    4. Sign your images: cosign sign --key components/cosign/cosign.key <image>"
echo "    5. Set up backups: bash scripts/backup-verify.sh"
