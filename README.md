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
│  only, no root containers, read-only rootfs,         │
│  RBAC enforcement (no default SA tokens)             │
├─────────────────────────────────────────────────────┤
│  OpenBao/Vault — dynamic secrets (15m rotation),     │
│  TPM auto-unseal, PKI, transit encryption            │
├─────────────────────────────────────────────────────┤
│  cert-manager — automated TLS via Vault PKI,         │
│  30-day certs with 7-day auto-renewal                │
├─────────────────────────────────────────────────────┤
│  Kanidm — passwordless SSO, WebAuthn/Passkeys,       │
│  OAuth2 provider for dashboard + Headscale           │
├─────────────────────────────────────────────────────┤
│  Mayastor (NVMe block) + RustFS (WORM object)        │
│  — encrypted at rest, Vault-managed keys             │
├─────────────────────────────────────────────────────┤
│  VictoriaMetrics — metrics + alerting (OOM,          │
│  crashes, security events, cert expiry, disk)        │
├─────────────────────────────────────────────────────┤
│  VictoriaLogs — tamper-evident audit logging          │
├─────────────────────────────────────────────────────┤
│  Headscale — Tailscale-compatible mesh VPN           │
│  (only path into the cluster)                        │
├─────────────────────────────────────────────────────┤
│  SurrealDB (database) + Stalwart (JMAP email)        │
│  + SimpleX Chat (SMP + XFTP relay) + Registry        │
│  + Web Dashboard (OIDC-authenticated)                │
│  + Automated Backup (encrypted CronJob)              │
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

1. Kyverno (admission control)
2. Tetragon (runtime security)
3. VictoriaLogs (audit logging)
4. VictoriaMetrics (metrics + alerting)
5. Vault/OpenBao (secrets management)
6. cert-manager (TLS automation via Vault PKI)
7. Mayastor (block storage)
8. Registry (local container images)
9. Kanidm (identity/OIDC)
10. Headscale (mesh VPN)
11. SurrealDB (database)
12. Stalwart (JMAP email)
13. RustFS (WORM object storage)
14. SimpleX Chat (secure messaging relay)
15. Web dashboard (OIDC-authenticated)
16. Backup (encrypted CronJob every 6h)

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
- No unauthenticated dashboard access (OIDC via Kanidm)
- No static TLS certificates (cert-manager auto-rotation via Vault PKI)
- No default ServiceAccount tokens (Kyverno enforced)
- No blind spots (VictoriaMetrics alerting on OOM, crashes, security events)

## Hardware Gaps

See [HARDWARE-GAPS.md](HARDWARE-GAPS.md) for physical security items to acquire.

## Directory Structure

```
slam-stack/
├── talos/              # Talos machine configs (controlplane + worker)
├── components/
│   ├── cilium/         # CNI + WireGuard + network policies
│   ├── kyverno/        # Admission control + image signing + RBAC enforcement
│   ├── tetragon/       # eBPF runtime security policies
│   ├── vault/          # OpenBao/Vault install + dynamic secrets
│   ├── cert-manager/   # TLS automation via Vault PKI
│   ├── victoria-logs/  # Audit log aggregation
│   ├── victoria-metrics/ # Metrics collection + alerting
│   ├── kanidm/         # Identity provider (WebAuthn + OAuth2)
│   ├── mayastor/       # NVMe-oF block storage
│   ├── rustfs/         # WORM object storage
│   ├── headscale/      # Mesh VPN
│   ├── simplex/        # Secure messaging (SMP + XFTP relay)
│   ├── surreal-db/     # Multi-model database
│   ├── stalwart/       # JMAP email server
│   ├── kata/           # MicroVM runtime class
│   ├── registry/       # Local container registry
│   ├── backup/         # Encrypted etcd backup CronJob
│   ├── flux/           # GitOps bootstrap (skeleton)
│   └── cosign/         # Image signing keys
├── dev/                # Dev environment setup
├── scripts/            # Backup, verification utilities
├── web/                # Dashboard (Leptos + Axum, OIDC-authenticated)
├── bootstrap.sh        # Full stack bootstrap
├── deploy.sh           # Component deployer
├── verify.sh           # Security verification suite
├── HARDWARE-GAPS.md    # Physical items to acquire
└── SECURITY-MANIFESTO.md  # Threat model and design principles
```

## Resource Budget (8GB single node, 16GB recommended)

| Component | CPU Request | Mem Request | Mem Limit |
|-----------|-------------|-------------|-----------|
| Cilium | 100m | 256Mi | 512Mi |
| Kyverno | 100m | 128Mi | 512Mi |
| Tetragon | 100m | 128Mi | 512Mi |
| VictoriaLogs | 100m | 256Mi | 384Mi |
| VictoriaMetrics | 100m | 128Mi | 256Mi |
| Vault | 100m | 256Mi | 512Mi |
| cert-manager | 100m | 128Mi | 256Mi |
| Mayastor | 200m | 384Mi | 512Mi |
| SurrealDB | 200m | 256Mi | 384Mi |
| Kanidm | 100m | 128Mi | 256Mi |
| Headscale | 50m | 64Mi | 256Mi |
| Stalwart | 100m | 128Mi | 512Mi |
| RustFS | 100m | 256Mi | 256Mi |
| SimpleX SMP | 50m | 64Mi | 128Mi |
| SimpleX XFTP | 50m | 64Mi | 128Mi |
| Registry | 50m | 64Mi | 256Mi |
| Web Dashboard | 50m | 32Mi | 128Mi |
| **Total** | **~1.9** | **~3.1Gi** | **~5.9Gi** |

Fits in 8GB (~6.5GB available after Talos). **16GB strongly recommended** for headroom.

## License

Private repository. All rights reserved.
