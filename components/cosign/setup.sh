#!/usr/bin/env bash
# Slam Stack — Cosign Key Generation & Setup
# Run this on an AIRGAPPED, TRUSTED machine.
# The private key should live ONLY on your YubiKey or hardware token.
set -euo pipefail

info()  { echo -e "\033[0;34m[*]\033[0m $1"; }
ok()    { echo -e "\033[0;32m[+]\033[0m $1"; }

# === Check for cosign ===
if ! command -v cosign &>/dev/null; then
  info "Installing cosign..."
  COSIGN_VERSION=$(curl -s https://api.github.com/repos/sigstore/cosign/releases/latest | grep tag_name | cut -d'"' -f4)
  curl -sL "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)" -o /usr/local/bin/cosign
  chmod +x /usr/local/bin/cosign
  ok "cosign installed"
fi

# === Generate key pair (hardware-backed) ===
if [ -f cosign.key ]; then
  info "cosign.key already exists. Remove it first to regenerate."
else
  info "Generating Cosign keypair..."
  info "SAVE THE PRIVATE KEY TO YOUR YUBIKEY PIV SLOT AFTER GENERATION."
  cosign generate-key-pair
  ok "Keys generated: cosign.key (PRIVATE — never share), cosign.pub (PUBLIC — safe to distribute)"
fi

# === Create Kubernetes secret ===
info "Creating Kyverno cosign public key secret..."
kubectl create secret generic cosign-public-key \
  -n kyverno \
  --from-file=cosign.pub=cosign.pub \
  --dry-run=client -o yaml | kubectl apply -f -
ok "Public key stored in kyverno/cosign-public-key"

echo ""
info "=== COSIGN SETUP COMPLETE ==="
info "Private key location: $(pwd)/cosign.key"
info "Store this on your YubiKey:"
echo "  cat cosign.key | ykman piv import-key --pin-policy=once --touch-policy=always 9a -"
echo ""
info "Then delete cosign.key from disk."
echo ""
info "To sign an image:"
echo "  cosign sign --key cosign.key <image>"
