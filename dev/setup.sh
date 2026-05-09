#!/usr/bin/env bash
# Slam Stack — Dev Environment Setup
# Spins up a Talos VM cluster via QEMU on Ubuntu
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${BLUE}[*]${NC} $1"; }
ok()    { echo -e "${GREEN}[+]${NC} $1"; }
fail()  { echo -e "${RED}[-]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_DIR="${SCRIPT_DIR}/patches"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ARCH=$(uname -m)
case "$ARCH" in x86_64) ARCH="amd64" ;; aarch64) ARCH="arm64" ;; *) fail "unsupported arch: $ARCH" ;; esac

# === Version pins ===
TALOS_VERSION="v1.13.0"
KUBECTL_VERSION="v1.32.0"
HELM_VERSION="3.17.0"
COSIGN_VERSION="v2.4.1"
TALOSCTL="${PROJECT_DIR}/_out/talosctl"

mkdir -p "${PROJECT_DIR}/_out"

# Check for k3s on host
if systemctl is-active --quiet k3s 2>/dev/null; then
  info "Stopping host k3s service (conflicts with Talos load balancer)..."
  sudo systemctl disable --now k3s.service
fi

# === Install talosctl ===
if ! command -v talosctl &>/dev/null && [ ! -f "$TALOSCTL" ]; then
  info "Installing talosctl ${TALOS_VERSION}..."
  curl -sSL --retry 3 "https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/talosctl-linux-${ARCH}" -o "$TALOSCTL"
  chmod +x "$TALOSCTL"
  sudo cp "$TALOSCTL" /usr/local/bin/talosctl
  ok "talosctl installed: $TALOS_VERSION"
fi

# === Install kubectl ===
if ! command -v kubectl &>/dev/null; then
  info "Installing kubectl ${KUBECTL_VERSION}..."
  curl -sSL --retry 3 "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" -o /tmp/kubectl
  chmod +x /tmp/kubectl && sudo mv /tmp/kubectl /usr/local/bin/kubectl
  ok "kubectl installed: ${KUBECTL_VERSION}"
fi

# === Install Helm ===
if ! command -v helm &>/dev/null; then
  info "Installing Helm ${HELM_VERSION}..."
  curl -sL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${ARCH}.tar.gz" | tar xz -C /tmp/
  sudo mv "/tmp/linux-${ARCH}/helm" /usr/local/bin/helm
  ok "helm installed: ${HELM_VERSION}"
fi

# === Install Cosign ===
if ! command -v cosign &>/dev/null; then
  info "Installing Cosign ${COSIGN_VERSION}..."
  curl -sSL --retry 3 "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-${ARCH}" -o /tmp/cosign
  chmod +x /tmp/cosign && sudo mv /tmp/cosign /usr/local/bin/cosign
  ok "cosign installed: ${COSIGN_VERSION}"
fi

# === Check QEMU ===
if ! command -v qemu-system-x86_64 &>/dev/null; then
  info "Installing QEMU..."
  sudo apt-get update -qq && sudo apt-get install -y -qq qemu-system libvirt-daemon-system bridge-utils uidmap
  sudo usermod -aG libvirt,kvm "$USER" 2>/dev/null || true
  ok "QEMU/KVM installed"
fi

# === Download Talos kernel/initramfs ===
info "Downloading Talos kernel/initramfs for ${TALOS_VERSION}..."
sudo mkdir -p /root/_out
GH_BASE="https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}"
sudo curl -sL -o /root/_out/vmlinuz-${ARCH} "${GH_BASE}/vmlinuz-${ARCH}"
sudo curl -sL -o /root/_out/initramfs-${ARCH}.xz "${GH_BASE}/initramfs-${ARCH}.xz"

# === Add Helm repos ===
helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
helm repo update 2>/dev/null || true

# === Clean previous cluster ===
sudo talosctl cluster destroy --name slam-stack-dev 2>/dev/null || true
sudo rm -rf /root/.talos/clusters/slam-stack-dev

# === Create dev cluster with hardening ===
info "Creating Slam Stack dev cluster (1 controlplane)..."

CREATE_CMD="cluster create"
if talosctl cluster create dev --help &>/dev/null 2>&1; then
  CREATE_CMD="cluster create dev"
fi

# Run talosctl as root from /root (so _out/ is found by QEMU)
sudo bash -c "
cd /root
${TALOSCTL} ${CREATE_CMD} \
  --name slam-stack-dev \
  --controlplanes 1 \
  --workers 0 \
  --memory 4GiB \
  --cpus 4 \
  --disk 20480 \
  --mtu 1500 \
  --wait=false \
  --skip-k8s-node-readiness-check \
  --skip-kubeconfig \
  --config-patch @${PATCH_DIR}/harden.yaml \
  --config-patch @${PATCH_DIR}/cilium.yaml
"

# === Wait for Talos health ===
info "Waiting for Talos health..."
sudo talosctl --talosconfig /root/.talos/config --nodes 10.5.0.2 health --wait-timeout=5m --server=false

# === Extract kubeconfig ===
info "Extracting kubeconfig..."
mkdir -p ~/.kube
sudo talosctl --talosconfig /root/.talos/config --nodes 10.5.0.2 kubeconfig /tmp/slam-kubeconfig --merge=false

# Fix: use server cert as CA & connect directly to VM
SERVER_CA=\$(echo | timeout 5 openssl s_client -connect 10.5.0.2:6443 -showcerts 2>/dev/null | timeout 5 openssl x509 2>/dev/null | base64 | tr -d '\n')
sudo python3 -c \"
import yaml
with open('/tmp/slam-kubeconfig') as f:
    d = yaml.safe_load(f)
d['clusters'][0]['cluster']['certificate-authority-data'] = '\${SERVER_CA}'
d['clusters'][0]['cluster']['server'] = 'https://10.5.0.2:6443'
with open('\${HOME}/.kube/slam-stack-config', 'w') as f:
    yaml.dump(d, f)
\"
sudo chown \$(id -u):\$(id -g) ~/.kube/slam-stack-config
ok "Kubeconfig: ~/.kube/slam-stack-config"

export KUBECONFIG=~/.kube/slam-stack-config
kubectl cluster-info 2>/dev/null | head -3

# === Install Cilium ===
info "Installing Cilium..."
helm upgrade --install cilium cilium/cilium \
  --version 1.16.5 \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=10.5.0.2 \
  --set k8sServicePort=6443 \
  --set encryption.enabled=true \
  --set encryption.type=wireguard \
  --set l7Proxy=false \
  --set ipam.mode=kubernetes \
  --set ipv4.enabled=true \
  --set ipv6.enabled=false \
  --set routingMode=native \
  --set autoDirectNodeRoutes=true \
  --set ipv4NativeRoutingCIDR=10.244.0.0/16 \
  --set hubble.enabled=false \
  --set operator.replicas=1 \
  --set securityContext.privileged=true \
  --wait --timeout 5m

kubectl wait --for=condition=ready node --all --timeout=2m

ok "=== Slam Stack Dev Cluster Ready ==="
echo ""
info "Components installed: Cilium (CNI + WireGuard)"
echo ""
echo "  export KUBECONFIG=~/.kube/slam-stack-config"
echo "  kubectl get nodes"
echo ""
info "Next: ./deploy.sh"
