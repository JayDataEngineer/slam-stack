#!/usr/bin/env bash
# Slam Stack — Web Dashboard Builder
# Builds the Leptos + Axum web app and creates a container image.
# Usage: ./build.sh [--push] [--registry registry.web.svc.cluster.local:5000]
set -euo pipefail

WEB_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC2034  # retained for potential future use
PROJECT_DIR="$(cd "${WEB_DIR}/.." && pwd)"
REGISTRY="${2:-localhost:5000}"
IMAGE_TAG="${REGISTRY}/slam-stack-web:latest"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${BLUE}[*]${NC} $1"; }
ok()    { echo -e "${GREEN}[+]${NC} $1"; }
fail()  { echo -e "${RED}[-]${NC} $1"; exit 1; }

# === Check for Rust ===
if ! command -v rustc &>/dev/null; then
  info "Installing Rust..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
  source "${HOME}/.cargo/env"
  ok "Rust installed: $(rustc --version)"
fi

# === Install cargo-leptos ===
if ! command -v cargo-leptos &>/dev/null; then
  info "Installing cargo-leptos..."
  cargo install cargo-leptos --locked 2>&1 | tail -3
  ok "cargo-leptos installed"
fi

# === Build ===
info "Building web dashboard..."
cd "$WEB_DIR"
cargo leptos build --release -vv 2>&1 | tail -5
ok "Build complete"

# === Check for container runtime ===
BUILDER=""
for cmd in docker podman nerdctl; do
  if command -v "$cmd" &>/dev/null; then
    BUILDER="$cmd"
    break
  fi
done

if [ -z "$BUILDER" ]; then
  warn "No container runtime found (docker/podman/nerdctl). Skipping image build."
  info "Binary available at: ${WEB_DIR}/target/release/slam-stack-web"
  exit 0
fi

# === Build container image ===
info "Building container image: ${IMAGE_TAG}"
"$BUILDER" build -t "$IMAGE_TAG" -f "${WEB_DIR}/Dockerfile" "$WEB_DIR" 2>&1 | tail -3
ok "Image built: ${IMAGE_TAG}"

if [ "${1:-}" = "--push" ]; then
  info "Pushing to ${REGISTRY}..."
  "$BUILDER" push "$IMAGE_TAG" 2>&1 | tail -3
  ok "Image pushed"
fi

echo ""
info "To deploy: kubectl apply -f ${WEB_DIR}/deploy.yaml"
info "  (update deploy.yaml image to: ${IMAGE_TAG})"
