# Hardware Gaps — SLAM Stack

Physical security items needed to reach full security posture.
Each item is a hardening upgrade. The stack runs without them, but these close
the gaps between "very secure software" and "nation-state resistant."

---

## 1. YubiKey 5 Series (or equivalent FIDO2 token)

**Status:** Not yet acquired
**Est. cost:** $50-70
**Protects:** Cosign image signing keys, WebAuthn authentication, SSH certificate authority

Without it:
- Cosign private key lives on disk (can be stolen with physical access or root compromise)
- WebAuthn works with platform authenticators (TPM) but a hardware token provides a second factor you can physically control

Migration path:
1. Acquire YubiKey 5 NFC or YubiKey 5C
2. `cosign generate-key-pair --kms yubikey://slot-id`
3. Re-sign all container images: `cosign sign --key yubikey://slot-id <image>`
4. Update `components/kyverno/signature-policy.yaml` with new public key
5. Destroy the old `cosign.key` file: `shred -u components/cosign/cosign.key`
6. Enable YubiKey-backed SSH: `ykman ssh-keys generate`

---

## 2. TPM 2.0 Module

**Status:** Verify presence — most modern Intel/AMD systems have firmware TPM
**Check:** `tpm2_getcap properties-fixed` on the host

If missing:
- Disk encryption keys are still LUKS2 but not hardware-bound
- An attacker with physical access can clone the disk and brute-force offline
- Measured boot attestation is not possible

Migration path:
1. If firmware TPM exists: enable in BIOS/UEFI (Intel PTT or AMD fTPM)
2. If no firmware TPM: purchase discrete TPM 2.0 module for motherboard (~$15-25)
3. After enabling: `talosctl apply-config` with existing config (Talos auto-binds LUKS to TPM)

---

## 3. Second Storage Disk (/dev/sdb)

**Status:** Verify presence — needed for Mayastor storage pool
**Check:** `lsblk` on the host

If missing:
- Mayastor has no dedicated block device for replicated storage
- Workarounds: use a partition on the same disk, or use local-path provisioner instead

Recommendation:
- Any NVMe or SSD, 256GB minimum
- Separate from OS disk for performance and isolation

---

## 4. Optional: Second Node for Backup Replication

**Status:** Not required for initial deployment
**Est. cost:** Any machine with 4GB+ RAM (~$100 used mini PC)

Purpose:
- Offsite encrypted etcd snapshot replication
- RustFS WORM backup target (air-gapped copy)
- Does NOT need to run the full stack — just RustFS + a cron pull

Migration path:
1. Install Talos on second node
2. Configure WireGuard tunnel between nodes (via Headscale)
3. `rsync` encrypted, signed backups from primary to secondary on schedule
4. Second node stays powered off between syncs (wake-on-LAN)

---

## Priority Order

1. **TPM** — check first, may already exist (firmware TPM). Free to enable.
2. **YubiKey** — closes the biggest gap (signing keys on disk). $50.
3. **Second disk** — needed for Mayastor. Check what's available.
4. **Backup node** — nice to have, not day-1 critical.
