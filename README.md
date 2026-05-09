# SLAM Stack

**Secure Lightweight Aggressive Minimal** — a single-node Kubernetes cluster hardened against nation-state adversaries, designed to run on 8GB RAM.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Hardware TPM 2.0                  │
├─────────────────────────────────────────────────────┤
│  Talos Linux — immutable OS, no SSH, API-only mTLS  │
├─────────────────────────────────────────────────────┤
│  Kata/Cloud Hypervisor — optional microVM isolation  │
├─────────────────────────────────────────────────────┤
│  Cilium + WireGuard — encrypted pod traffic,         │
│  default-deny microsegmentation                      │
├─────────────────────────────────────────────────────┤
│  Tetragon — eBPF kernel-level process enforcement    │
├─────────────────────────────────────────────────────┤
│  Kyverno + Cosign — admission control, signed images │
│  only, no root containers, read-only rootfs          │
├─────────────────────────────────────────────────────┤
│  OpenBao/Vault — dynamic secrets (15m rotation),     │
│  TPM auto-unseal, PKI, transit encryption            │
├─────────────────────────────────────────────────────┤
│  Kanidm — passwordless SSO, WebAuthn/Passkeys only   │
├─────────────────────────────────────────────────────┤
│  Mayastor (NVMe block) + RustFS (WORM object)        │
│  — encrypted at rest, Vault-managed keys             │
├─────────────────────────────────────────────────────┤
│  VictoriaLogs — tamper-evident audit logging          │
├─────────────────────────────────────────────────────┤
│  Headscale — Tailscale-compatible mesh VPN           │
│  (only path into the cluster)                        │
├─────────────────────────────────────────────────────┤
│  SurrealDB (database) + Stalwart (JMAP email)        │
│  + SimpleX Chat (SMP + XFTP relay) + Registry        │
│  + Web Dashboard                                     │
└─────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

- Machine with TPM 2.0 (check: `tpm2_getcap properties-fixed`)
- 8GB+ RAM, two disks (OS + storage)
- Ubuntu 26.04 dev machine for bootstrap

### Bootstrap

```bash
# Clone
git clone <repo> && cd slam-stack

# Set your cluster endpoint
export CLUSTER_API_ENDPOINT="10.0.0.2:50000"

# Run bootstrap
./bootstrap.sh --dev
```

### What Gets Installed

All components deploy in dependency order via `deploy.sh`:

1. Cilium (CNI + WireGuard encryption)
2. Kyverno (admission control)
3. Tetragon (runtime security)
4. VictoriaLogs (audit logging)
5. Vault/OpenBao (secrets management)
6. Mayastor (block storage)
7. Registry (local container images)
8. Kanidm (identity/OIDC)
9. Headscale (mesh VPN)
10. SurrealDB (database)
11. Stalwart (JMAP email)
12. RustFS (WORM object storage)
13. SimpleX Chat (secure messaging relay)
14. Web dashboard

### Verify

```bash
./verify.sh
```

## Security Posture

See [SECURITY-MANIFESTO.md](SECURITY-MANIFESTO.md) for the full threat model and design principles.

**Key guarantees:**
- No unsigned images can run (Cosign + Kyverno enforcement)
- No shell execution inside pods (Tetragon kills at kernel level)
- No pod-to-pod traffic without explicit policy (Cilium default-deny)
- No secrets on disk (Vault tmpfs, 15-minute rotation)
- No inbound ports (Headscale mesh only)
- No passwords (WebAuthn/Passkeys only)

## Hardware Gaps

See [HARDWARE-GAPS.md](HARDWARE-GAPS.md) for physical security items to acquire.

## Directory Structure

```
slam-stack/
├── talos/              # Talos machine configs (controlplane + worker)
├── components/
│   ├── cilium/         # CNI + WireGuard + network policies
│   ├── kyverno/        # Admission control + image signing
│   ├── tetragon/       # eBPF runtime security policies
│   ├── vault/          # OpenBao/Vault install + dynamic secrets
│   ├── kanidm/         # Identity provider (WebAuthn)
│   ├── mayastor/       # NVMe-oF block storage
│   ├── rustfs/         # WORM object storage
│   ├── victoria-logs/  # Audit log aggregation
│   ├── headscale/      # Mesh VPN
│   ├── simplex/        # Secure messaging (SMP + XFTP relay)
│   ├── surreal-db/     # Multi-model database
│   ├── stalwart/       # JMAP email server
│   ├── kata/           # MicroVM runtime class
│   ├── registry/       # Local container registry
│   ├── flux/           # GitOps bootstrap (skeleton)
│   └── cosign/         # Image signing keys
├── dev/                # Dev environment setup
├── scripts/            # Backup, verification utilities
├── web/                # Dashboard (Leptos + Axum)
├── bootstrap.sh        # Full stack bootstrap
├── deploy.sh           # Component deployer
├── verify.sh           # Security verification suite
├── HARDWARE-GAPS.md    # Physical items to acquire
└── SECURITY-MANIFESTO.md  # Threat model and design principles
```

## Resource Budget (8GB single node)

| Component | CPU Request | Mem Request | Mem Limit |
|-----------|-------------|-------------|-----------|
| Cilium | 100m | 256Mi | 512Mi |
| Kyverno | 100m | 128Mi | 512Mi |
| Tetragon | 100m | 128Mi | 512Mi |
| Vault | 100m | 256Mi | 512Mi |
| Kanidm | 100m | 128Mi | 256Mi |
| SurrealDB | 200m | 256Mi | 384Mi |
| VictoriaLogs | 100m | 256Mi | 384Mi |
| Mayastor | 200m | 384Mi | 512Mi |
| RustFS | 100m | 256Mi | 256Mi |
| Stalwart | 100m | 128Mi | 512Mi |
| Headscale | 50m | 64Mi | 256Mi |
| SimpleX SMP | 50m | 64Mi | 128Mi |
| SimpleX XFTP | 50m | 64Mi | 128Mi |
| Registry | 50m | 64Mi | 256Mi |
| **Total** | **~1.7** | **~2.8Gi** | **~5.5Gi** |

Fits in 8GB with ~1.5GB for Talos overhead. SimpleX adds ~256Mi total — lightweight.

## License

Private repository. All rights reserved.
