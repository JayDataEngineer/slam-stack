#!/usr/bin/env bash
# Slam Stack — Build and push backup image
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REGISTRY="${1:-registry.registry.svc.cluster.local:5000}"
IMAGE="${REGISTRY}/slam-stack-backup:latest"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; NC='\033[0m'
info()  { echo -e "${BLUE}[*]${NC} $1"; }
ok()    { echo -e "${GREEN}[+]${NC} $1"; }

BUILDER=""
for cmd in docker podman nerdctl; do
  if command -v "$cmd" &>/dev/null; then
    BUILDER="$cmd"
    break
  fi
done

[ -z "$BUILDER" ] && { echo "No container runtime found"; exit 1; }

info "Building backup image..."
"$BUILDER" build -t "$IMAGE" -f "${SCRIPT_DIR}/Dockerfile" "${PROJECT_DIR}" 2>&1 | tail -5
ok "Built: ${IMAGE}"

if [ "${2:-}" = "--push" ]; then
  info "Pushing to ${REGISTRY}..."
  "$BUILDER" push "$IMAGE" 2>&1 | tail -3
  ok "Pushed"
fi
