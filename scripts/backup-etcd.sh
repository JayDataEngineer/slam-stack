#!/usr/bin/env bash
# Slam Stack — etcd Backup Script
# Creates encrypted, snapshotted etcd backups to RustFS/MinIO
# Run as a CronJob in production.
set -euo pipefail

SNAPSHOT_FILE="/tmp/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db"
BACKUP_BUCKET="s3://slamstack-backups/etcd/"
RETENTION_DAYS=30

info() { echo -e "\033[0;34m[*]\033[0m $1"; }
ok()   { echo -e "\033[0;32m[+]\033[0m $1"; }

# === Take snapshot via Talos API ===
info "Creating etcd snapshot..."
talosctl etcd snapshot "$SNAPSHOT_FILE" --cluster slam-stack-dev
ok "Snapshot created: $SNAPSHOT_FILE ($(du -h "$SNAPSHOT_FILE" | cut -f1))"

# === Encrypt before upload ===
info "Encrypting snapshot..."
gpg --symmetric --cipher-algo AES256 --batch --passphrase-file /etc/backup/gpg-passphrase \
  -o "${SNAPSHOT_FILE}.gpg" "$SNAPSHOT_FILE"
rm -f "$SNAPSHOT_FILE"
ok "Encrypted: ${SNAPSHOT_FILE}.gpg"

# === Upload to RustFS/MinIO ===
if command -v s3cmd &>/dev/null; then
  info "Uploading to S3-compatible storage..."
  s3cmd put "${SNAPSHOT_FILE}.gpg" "$BACKUP_BUCKET"
  ok "Uploaded to $BACKUP_BUCKET"
else
  info "s3cmd not available — snapshot saved locally at ${SNAPSHOT_FILE}.gpg"
fi

# === Rotate old backups ===
info "Cleaning backups older than $RETENTION_DAYS days..."
find /tmp -name "etcd-snapshot-*.gpg" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
if command -v s3cmd &>/dev/null; then
  s3cmd ls "$BACKUP_BUCKET" | while read -r line; do
    DATE=$(echo "$line" | awk '{print $1}')
    if [ -n "$DATE" ] && [ "$(date -d "$DATE" +%s)" -lt "$(date -d "-$RETENTION_DAYS days" +%s)" ]; then
      FILE=$(echo "$line" | awk '{print $4}')
      s3cmd del "$FILE"
    fi
  done
fi

ok "Backup complete"
