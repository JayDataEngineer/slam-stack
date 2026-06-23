#!/usr/bin/env bash
#
# Downloads a Talos Linux qcow2 image directly from factory.talos.dev.
#
# The factory serves qcow2 natively, so no qemu-img conversion is needed.
# Idempotent: skips if the destination already exists.
#
# Args: schematic_id talos_version cpu_arch cache_dir
set -euo pipefail

SCHEMATIC="$1"
VERSION="$2"
ARCH="$3"
CACHE_DIR="$4"

case "$ARCH" in
  amd64) factory_arch="metal-amd64" ;;
  arm64) factory_arch="metal-arm64" ;;
  *) echo "ERROR: unsupported arch '$ARCH' (want amd64|arm64)" >&2; exit 2 ;;
esac

DEST="$CACHE_DIR/talos-${VERSION}-${ARCH}.qcow2"
URL="https://factory.talos.dev/image/${SCHEMATIC}/${VERSION}/${factory_arch}.qcow2"

if [[ -f "$DEST" ]]; then
  echo "[fetch-talos] cache hit: $DEST"
  exit 0
fi

mkdir -p "$CACHE_DIR"

echo "[fetch-talos] downloading $URL"
curl --fail --location --progress-bar "$URL" -o "$DEST"

echo "[fetch-talos] base image size: $(du -h "$DEST" | cut -f1)"
echo "[fetch-talos] done → $DEST"
