# SLAM Stack

**Secure Lightweight Aggressive Minimal** — a single-node Kubernetes cluster hardened against nation-state adversaries, designed to run on 8GB RAM.

## Flavors

The SLAM Stack comes in three flavors, selected via the `FLAVOR` env var:

| Flavor | Components | Use Case |
|--------|-----------|----------|
| **`core`** | Infrastructure only: Cilium, Tetragon, Kyverno, Vault, cert-manager, Kanidm, Headscale, Mayastor, RustFS, CNPG, VictoriaMetrics, VictoriaLogs, Registry, Web Dashboard, Backup | Build your own app on a hardened base |
| **`og`** (default) | Core + Stalwart (JMAP email) + SimpleX Chat (SMP + XFTP relay) | Maximum privacy — metadata-free messaging, self-hosted email |
| **`matrix`** | Core + Continuwuity/Tuwunel (Matrix homeserver) + Cinny (Discord-like UI) + LiveKit (E2EE voice/video) | Discord-clone for teams with E2EE, OIDC-backed |

```bash
# Deploy with OG flavor (default)
./deploy.sh

# Deploy with Matrix flavor
FLAVOR=matrix ./deploy.sh

# Deploy core only
FLAVOR=core ./deploy.sh
```

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
│  cert-manager — automated TLS via Vault PKI,         │
│  30-day certs with 7-day auto-renewal                │
├─────────────────────────────────────────────────────┤
│  Kanidm — passwordless SSO, WebAuthn/Passkeys,       │
│  OAuth2 provider for dashboard + flavor apps         │
├─────────────────────────────────────────────────────┤
│  Mayastor (NVMe block) + RustFS (WORM object)        │
│  — encrypted at rest, Vault-managed keys             │
├─────────────────────────────────────────────────────┤
│  VictoriaMetrics — metrics + alerting                │
├─────────────────────────────────────────────────────┤
│  VictoriaLogs — tamper-evident audit logging          │
├─────────────────────────────────────────────────────┤
│  Headscale — Tailscale-compatible mesh VPN           │
│  (only path into the cluster)                        │
├─────────────────────────────────────────────────────┤
│  ┌───────────────────────────────────────────────┐  │
│  │  Flavor Layer (OG / Matrix / Custom)           │  │
│  │  • OG: Stalwart email + SimpleX Chat          │  │
│  │  • Matrix: Continuwuity + Cinny + LiveKit     │  │
│  └───────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────┤
│  PostgreSQL/CNPG + Registry + Web Dashboard + Backup │
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

# Boot with OG flavor (default — Stalwart + SimpleX)
./bootstrap.sh --dev

# Boot with Matrix flavor (Continuwuity + Cinny + LiveKit)
FLAVOR=matrix ./bootstrap.sh --dev

# Boot core only (no application components)
FLAVOR=core ./bootstrap.sh --dev
```

### What Gets Installed

All components deploy in dependency order via `deploy.sh`.

**Core (all flavors):**
1. Cilium (CNI + WireGuard + default-deny policies)
2. Kyverno (admission control + Cosign image signing)
3. Tetragon (eBPF runtime security)
4. VictoriaLogs (immutable audit logging)
5. VictoriaMetrics (metrics + alerting)
6. Vault/OpenBao (dynamic secrets, PKI, TPM auto-unseal)
7. cert-manager (TLS automation via Vault PKI)
8. Mayastor (NVMe-oF block storage)
9. CNPG (PostgreSQL operator)
10. PostgreSQL (database with pgAudit)
11. Registry (local container images)
12. Kanidm (identity/OIDC, WebAuthn/Passkeys)
13. Headscale (Tailscale-compatible mesh VPN)
14. RustFS (WORM object storage)
15. Web dashboard (OIDC-authenticated)
16. Backup (encrypted CronJob)

**OG flavor** additionally deploys:
17. Stalwart (JMAP email server)
18. SimpleX Chat (SMP relay + XFTP file relay)

**Matrix flavor** additionally deploys:
17. Continuwuity/Tuwunel (Rust-based Matrix homeserver)
18. Cinny (Discord-like web UI)
19. LiveKit (E2EE voice/video channels)

### Verify

```bash
./verify.sh
FLAVOR=matrix ./verify.sh
```

## Security Posture

See [SECURITY-MANIFESTO.md](SECURITY-MANIFESTO.md) for the full threat model and design principles.

**Key guarantees:**
- No unsigned images can run (Cosign + Kyverno enforcement)
- No shell execution inside pods (Tetragon kills at kernel level)
- No pod-to-pod traffic without explicit policy (Cilium default-deny)
- No secrets on disk (Vault tmpfs, 15-minute rotation)
- No inbound ports (Headscale mesh only)
- No passwords (WebAuthn/Passkeys only, or TOTP per flavor)
- No unauthenticated dashboard access (OIDC via Kanidm)
- No static TLS certificates (cert-manager auto-rotation via Vault PKI)
- No default ServiceAccount tokens (Kyverno enforced)
- No blind spots (VictoriaMetrics alerting on OOM, crashes, security events)

## Directory Structure

```
slam-stack/
├── talos/              # Talos machine configs (controlplane + worker)
├── components/         # Core infrastructure (shared across all flavors)
│   ├── cilium/         # CNI + WireGuard + network policies
│   ├── kyverno/        # Admission control + image signing
│   ├── tetragon/       # eBPF runtime security policies
│   ├── vault/          # OpenBao/Vault install + dynamic secrets
│   ├── cert-manager/   # TLS automation via Vault PKI
│   ├── victoria-logs/  # Audit log aggregation
│   ├── victoria-metrics/ # Metrics collection + alerting
│   ├── kanidm/         # Identity provider (WebAuthn + OAuth2)
│   ├── mayastor/       # NVMe-oF block storage
│   ├── rustfs/         # WORM object storage
│   ├── headscale/      # Mesh VPN
│   ├── postgres/       # CNPG-managed PostgreSQL
│   ├── kata/           # MicroVM runtime class
│   ├── registry/       # Local container registry
│   ├── backup/         # Encrypted etcd backup CronJob
│   ├── flux/           # GitOps bootstrap (skeleton)
│   └── cosign/         # Image signing keys
├── flavors/            # Application flavors
│   ├── og/             # OG: Stalwart email + SimpleX chat
│   │   ├── components/ # stalwart/, simplex/ install.yaml
│   │   └── policies/   # OG-specific Cilium, cert, SA, OAuth2
│   └── matrix/         # Matrix: Continuwuity + Cinny + LiveKit
│       ├── components/ # matrix/, cinny/, livekit/ skeletons
│       └── policies/   # Matrix-specific policies (TBD)
├── dev/                # Dev environment setup
├── scripts/            # Backup, verification utilities
├── web/                # Dashboard (Leptos + Axum, OIDC-authenticated)
├── bootstrap.sh        # Full stack bootstrap
├── deploy.sh           # Component deployer (FLAVOR-aware)
├── verify.sh           # Security verification suite
├── Makefile            # Flavor-aware convenience targets
├── HARDWARE-GAPS.md    # Physical items to acquire
└── SECURITY-MANIFESTO.md  # Threat model and design principles
```

## Resource Budget (8GB single node, 16GB recommended)

### Core (all flavors)

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
| CNPG Operator | 50m | 100Mi | 256Mi |
| PostgreSQL | 100m | 128Mi | 384Mi |
| Kanidm | 100m | 128Mi | 256Mi |
| Headscale | 50m | 64Mi | 256Mi |
| RustFS | 100m | 256Mi | 256Mi |
| Registry | 50m | 64Mi | 256Mi |
| Web Dashboard | 50m | 32Mi | 128Mi |
| **Core Total** | **~1.3** | **~2.4Gi** | **~4.8Gi** |

### OG Flavor Add-on

| Component | CPU Request | Mem Request | Mem Limit |
|-----------|-------------|-------------|-----------|
| Stalwart | 100m | 128Mi | 512Mi |
| SimpleX SMP | 50m | 64Mi | 128Mi |
| SimpleX XFTP | 50m | 64Mi | 128Mi |
| **OG Total** | **~2.0** | **~3.3Gi** | **~6.3Gi** |

### Matrix Flavor Add-on (estimated)

| Component | CPU Request | Mem Request | Mem Limit |
|-----------|-------------|-------------|-----------|
| Continuwuity | 100m | 128Mi | 512Mi |
| Cinny | 50m | 32Mi | 128Mi |
| LiveKit | 100m | 256Mi | 1Gi |
| **Matrix Total** | **~1.7** | **~2.8Gi** | **~6.4Gi** |

Fits in 8GB (~6.5GB available after Talos). **16GB strongly recommended** for headroom.

## License

Private repository. All rights reserved.
