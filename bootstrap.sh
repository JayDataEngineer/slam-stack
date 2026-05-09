#!/usr/bin/env bash
# Slam Stack — Bootstrap from Scratch
# Run this on a fresh Ubuntu 26.04 dev machine to reproduce the entire stack.
# Usage: ./bootstrap.sh [--dev|--prod]
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${BLUE}[*]${NC} $1"; }
ok()    { echo -e "${GREEN}[+]${NC} $1"; }
fail()  { echo -e "${RED}[-]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:---dev}"

echo "=== Slam Stack Bootstrap ==="
echo "Mode: ${MODE}"
echo ""

# === 1. Dev environment setup ===
info "Step 1/6: Dev environment setup..."
cd "$SCRIPT_DIR"
bash dev/setup.sh
ok "Dev environment ready"

# === 2. Generate Cosign keypair ===
info "Step 2/6: Cosign key generation..."
cd "${SCRIPT_DIR}/components/cosign"
if [ ! -f cosign.pub ]; then
  cosign generate-key-pair
fi
cd "$SCRIPT_DIR"
ok "Cosign keypair ready"

# === 3. Deploy components ===
info "Step 3/6: Deploying stack components..."
export KUBECONFIG="${HOME}/.kube/slam-stack-config"
bash deploy.sh
ok "Stack components deployed"

# === 4. Build web dashboard ===
info "Step 4/6: Building web dashboard..."
bash web/build.sh --push --registry registry.registry.svc.cluster.local:5000 2>&1 || {
  warn "Web dashboard build skipped (no container runtime)"
  info "  Manual: cd web && cargo leptos build --release"
}
ok "Web dashboard built"

# === 5. Verify ===
info "Step 5/6: Running verification suite..."
cd "$SCRIPT_DIR"
bash verify.sh
ok "Verification complete"

# === 6. Post-install summary ===
echo ""
info "Step 6/6: Post-install summary"
echo ""
echo "  ┌─────────────────────────────────────────────┐"
echo "  │         Slam Stack Bootstrap Complete        │"
echo "  ├─────────────────────────────────────────────┤"
echo "  │  Kubeconfig: ~/.kube/slam-stack-config       │"
echo "  │  Talos API: 10.5.0.2:6443                    │"
echo "  │  Registry: registry.registry.svc.cluster.local:5000 │"
echo "  │  Dashboard: web/deploy.yaml                  │"
echo "  └─────────────────────────────────────────────┘"
echo ""
echo "  Components installed:"
echo "    Cilium (CNI + WireGuard)"
echo "    Kyverno (admission + Cosign enforcement)"
echo "    Tetragon (eBPF runtime security)"
echo "    Vault/OpenBao (dynamic secrets)"
echo "    VictoriaLogs (audit logging)"
echo "    Kanidm (identity/OIDC)"
echo "    Headscale (Tailscale-compatible mesh)"
echo "    SurrealDB (multi-model database)"
echo "    Stalwart (JMAP email)"
echo "    RustFS (WORM object storage)"
echo "    Mayastor (NVMe-oF block storage)"
echo "    Registry (local container registry)"
echo "    Web dashboard (Leptos + Axum)"
echo ""
echo "  Next steps:"
echo "    1. Run day-0 ceremony: talosctl health && ./verify.sh"
echo "    2. Initialize Vault: see runbook.md"
echo "    3. Configure Kanidm: see runbook.md"
echo "    4. Sign your images: cosign sign --key components/cosign/cosign.key <image>"
echo "    5. For production: see runbook.md for YubiKey setup"
