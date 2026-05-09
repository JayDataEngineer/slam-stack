#!/usr/bin/env bash
# Slam Stack — SOPS + Age Encryption Setup
# Encrypts secrets in Git for GitOps deployments.
# The Age private key should be stored on a YubiKey or hardware token.
set -euo pipefail

info()  { echo -e "\033[0;34m[*]\033[0m $1"; }
ok()    { echo -e "\033[0;32m[+]\033[0m $1"; }
warn()  { echo -e "\033[0;33m[!]\033[0m $1"; }

# === Install SOPS ===
if ! command -v sops &>/dev/null; then
  info "Installing SOPS..."
  SOPS_VERSION=$(curl -s https://api.github.com/repos/getsops/sops/releases/latest | grep tag_name | cut -d'"' -f4)
  curl -sL "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.$(uname -m)" -o /usr/local/bin/sops
  chmod +x /usr/local/bin/sops
  ok "SOPS installed: $(sops --version)"
fi

# === Install age ===
if ! command -v age-keygen &>/dev/null; then
  info "Installing age..."
  AGE_VERSION=$(curl -s https://api.github.com/repos/FiloSottile/age/releases/latest | grep tag_name | cut -d'"' -f4)
  curl -sL "https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/age-${AGE_VERSION}-linux-$(uname -m).tar.gz" | tar xz -C /tmp/
  sudo cp /tmp/age/age /tmp/age/age-keygen /usr/local/bin/
  rm -rf /tmp/age
  ok "age installed"
fi

# === Generate age key ===
AGE_KEY_FILE="${AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
if [ ! -f "$AGE_KEY_FILE" ]; then
  info "Generating age keypair..."
  mkdir -p "$(dirname "$AGE_KEY_FILE")"
  age-keygen -o "$AGE_KEY_FILE"
  ok "Age key generated: $AGE_KEY_FILE"
  warn "This is YOUR private key. Back it up to a YubiKey."
  warn "  cat $AGE_KEY_FILE | age -p > backup-encrypted.txt"
else
  ok "Age key exists: $AGE_KEY_FILE"
fi

# Extract public key
AGE_PUB_KEY=$(age-keygen -y "$AGE_KEY_FILE")
echo ""
info "Your age public key:"
echo "  $AGE_PUB_KEY"
echo ""

# === Create .sops.yaml config ===
cat > .sops.yaml << EOF
creation_rules:
  - path_regex: components/.*\.enc\.yaml
    age: >-
      $AGE_PUB_KEY
  - path_regex: talos/.*\.enc\.yaml
    age: >-
      $AGE_PUB_KEY
  - path_regex: dev/.*\.enc\.yaml
    age: >-
      $AGE_PUB_KEY
EOF
ok ".sops.yaml created"

# === Encrypt example secret ===
info "Creating example encrypted secret..."
cat > example-secret.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: slam-stack-secret
  namespace: default
type: Opaque
data:
  password: ""  # placeholder
EOF

sops --encrypt --in-place example-secret.yaml 2>/dev/null || true
ok "Example encrypted secret created"

echo ""
info "=== SOPS SETUP COMPLETE ==="
echo ""
echo "To encrypt a file:"
echo "  sops --encrypt --in-place path/to/file.yaml"
echo ""
echo "To decrypt a file:"
echo "  sops --decrypt path/to/file.enc.yaml"
echo ""
echo "To edit an encrypted file:"
echo "  sops path/to/file.enc.yaml"
