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

ARCH=$(uname -m)
case "$ARCH" in x86_64) ARCH="amd64" ;; aarch64) ARCH="arm64" ;; *) fail "unsupported arch: $ARCH" ;; esac
TALOS_VERSION="v1.13.0"
TALOSCTL="talosctl"

# Check for k3s on host (conflicts with Talos LB on port 6443)
if systemctl is-active --quiet k3s 2>/dev/null; then
  info "Stopping host k3s service (conflicts with Talos load balancer)..."
  sudo systemctl disable --now k3s.service
fi

# === Install talosctl ===
if ! command -v talosctl &>/dev/null; then
  info "Installing talosctl..."
  curl -sL "https://github.com/siderolabs/talos/releases/latest/download/talosctl-$(uname -s | tr '[:upper:]' '[:lower:]')-${ARCH}" -o /tmp/talosctl
  sudo mv /tmp/talosctl /usr/local/bin/talosctl && sudo chmod +x /usr/local/bin/talosctl
  ok "talosctl installed: $(talosctl version --client 2>/dev/null | head -1)"
fi

# === Install kubectl ===
if ! command -v kubectl &>/dev/null; then
  info "Installing kubectl..."
  curl -sLO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"
  chmod +x kubectl && sudo mv kubectl /usr/local/bin/
  ok "kubectl installed"
fi

# === Install Helm ===
if ! command -v helm &>/dev/null; then
  info "Installing Helm..."
  curl -sL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  ok "helm installed"
fi

# === Check QEMU ===
if ! command -v qemu-system-x86_64 &>/dev/null; then
  info "Installing QEMU..."
  sudo apt-get update -qq && sudo apt-get install -y -qq qemu-system libvirt-daemon-system bridge-utils uidmap
  sudo usermod -aG libvirt,kvm "$USER" 2>/dev/null || true
  ok "QEMU/KVM installed"
fi

# === Download Talos kernel/initramfs ===
info "Downloading Talos kernel/initramfs..."
sudo mkdir -p /root/_out
SUDO_HOME=$(sudo bash -c 'echo $HOME')
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

# Use the dev subcommand if available (Talos >= 1.13)
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

# === Wait for Talos health (skip k8s check, the LB SAN issue is handled below) ===
info "Waiting for Talos health..."
sudo talosctl --talosconfig /root/.talos/config --nodes 10.5.0.2 health --wait-timeout=5m --server=false

# === Extract kubeconfig ===
# The LB at 10.5.0.1:6443 terminates TLS, so we connect directly to the VM
info "Extracting kubeconfig..."
mkdir -p ~/.kube
sudo talosctl --talosconfig /root/.talos/config --nodes 10.5.0.2 kubeconfig /tmp/slam-kubeconfig --merge=false

# Fix the kubeconfig: use server cert as CA & connect directly to VM (bypasses LB TLS issues)
SERVER_CA=\$(echo | timeout 5 openssl s_client -connect 10.5.0.2:6443 -showcerts 2>/dev/null | timeout 5 openssl x509 2>/dev/null | base64 | tr -d '\n')
sudo python3 -c \"
import yaml
with open('/tmp/slam-kubeconfig') as f:
    d = yaml.safe_load(f)
d['clusters'][0]['cluster']['certificate-authority-data'] = '\${SERVER_CA}'
d['clusters'][0]['cluster']['server'] = 'https://10.5.0.2:6443'
with open('${HOME}/.kube/slam-stack-config', 'w') as f:
    yaml.dump(d, f)
\"
sudo chown $(id -u):$(id -g) ~/.kube/slam-stack-config
ok "Kubeconfig: ~/.kube/slam-stack-config"

export KUBECONFIG=~/.kube/slam-stack-config
kubectl cluster-info 2>/dev/null | head -3

# === Install Cilium (CNI, kube-proxy replacement, WireGuard) ===
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
info "Next: ./deploy.sh --dev"
