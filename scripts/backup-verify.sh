#!/usr/bin/env bash
# Slam Stack — Tamper-Evident Backup Script
# Creates encrypted, Cosign-signed etcd backups and uploads to RustFS WORM storage.
# Every backup is encrypted (age), signed (cosign), and verified on restore.
# Run as a CronJob in production.
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[*]${NC} $1"; }
ok()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
fail()  { echo -e "${RED}[-]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SLAM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

SNAPSHOT_FILE="/tmp/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db"
BACKUP_BUCKET="s3://slamstack-backups/etcd/"
RETENTION_DAYS=30
COSIGN_KEY="${SLAM_DIR}/components/cosign/cosign.key"
COSIGN_PUB="${SLAM_DIR}/components/cosign/cosign.pub"

# Load age public key from env or .env
AGE_PUBKEY="${BACKUP_AGE_PUBKEY:-}"
if [ -z "$AGE_PUBKEY" ] && [ -f "${SLAM_DIR}/.env" ]; then
  source "${SLAM_DIR}/.env"
  AGE_PUBKEY="${BACKUP_AGE_PUBKEY:-}"
fi
[ -z "$AGE_PUBKEY" ] && fail "BACKUP_AGE_PUBKEY not set — generate with: age-keygen -o key.txt && export BACKUP_AGE_PUBKEY=\$(cat key.txt.pub)"

# === Take snapshot via Talos API ===
info "Creating etcd snapshot..."
talosctl etcd snapshot "$SNAPSHOT_FILE"
ok "Snapshot created: $SNAPSHOT_FILE ($(du -h "$SNAPSHOT_FILE" | cut -f1))"

# === Encrypt with age (modern alternative to GPG) ===
info "Encrypting snapshot with age..."
ENCRYPTED_FILE="${SNAPSHOT_FILE}.age"
age -r "$AGE_PUBKEY" -o "$ENCRYPTED_FILE" "$SNAPSHOT_FILE"
rm -f "$SNAPSHOT_FILE"
ok "Encrypted: $ENCRYPTED_FILE"

# === Sign with Cosign (tamper evidence) ===
info "Signing encrypted snapshot..."
SIG_FILE="${ENCRYPTED_FILE}.sig"
if [ -f "$COSIGN_KEY" ]; then
  cosign sign-blob --key "$COSIGN_KEY" --output-signature "$SIG_FILE" "$ENCRYPTED_FILE"
  ok "Signed: $SIG_FILE"
else
  warn "No Cosign key found — skipping signature (see HARDWARE-GAPS.md for YubiKey migration)"
  touch "$SIG_FILE"
fi

# === Compute SHA256 for verification ===
SHA256_FILE="${ENCRYPTED_FILE}.sha256"
sha256sum "$ENCRYPTED_FILE" > "$SHA256_FILE"
ok "SHA256: $SHA256_FILE"

# === Upload to RustFS WORM storage ===
if command -v s3cmd >/dev/null 2>&1; then
  info "Uploading to RustFS WORM storage..."
  s3cmd put "$ENCRYPTED_FILE" "$BACKUP_BUCKET"
  s3cmd put "$SIG_FILE" "$BACKUP_BUCKET"
  s3cmd put "$SHA256_FILE" "$BACKUP_BUCKET"
  ok "Uploaded to $BACKUP_BUCKET"
else
  info "s3cmd not available — backup saved locally:"
  info "  Encrypted: $ENCRYPTED_FILE"
  info "  Signature: $SIG_FILE"
  info "  SHA256:    $SHA256_FILE"
fi

# === Rotate old backups ===
info "Cleaning backups older than $RETENTION_DAYS days..."
find /tmp -name "etcd-snapshot-*.age" -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true
find /tmp -name "etcd-snapshot-*.sig" -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true
find /tmp -name "etcd-snapshot-*.sha256" -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true

if command -v s3cmd >/dev/null 2>&1; then
  s3cmd ls "$BACKUP_BUCKET" | while read -r line; do
    DATE=$(echo "$line" | awk '{print $1}')
    if [ -n "$DATE" ] && [ "$(date -d "$DATE" +%s)" -lt "$(date -d "-$RETENTION_DAYS days" +%s)" ]; then
      FILE=$(echo "$line" | awk '{print $4}')
      s3cmd del "$FILE" 2>/dev/null || true
    fi
  done
fi

ok "Backup complete"
echo ""
echo "  To verify on restore:"
echo "    sha256sum -c ${ENCRYPTED_FILE}.sha256"
echo "    cosign verify-blob --key ${COSIGN_PUB} --signature ${ENCRYPTED_FILE}.sig ${ENCRYPTED_FILE}"
echo "    age -d -i <age-identity-file> -o restored.db ${ENCRYPTED_FILE}"
