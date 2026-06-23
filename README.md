# Slam Stack

**Secure Lightweight Aggressive Minimal** — a single-node Kubernetes
cluster hardened against nation-state adversaries, designed to run on
8 GB RAM. Talos Linux + Cilium + Kyverno + Cosign + OpenBao/Vault +
cert-manager + Kanidm + Headscale. GitOps via Flux. IaC via OpenTofu.

> **Resume project.** A from-scratch exploration of what a zero-trust
> Kubernetes platform looks like — every layer chosen for a defensible
> security reason, every component pinned, every image signature-
> verified, every pod default-denied. Six flavors ship: an ultra-minimal
> security plane, a pure-Rust backend stack, and three secure messaging
> stacks (OG, Matrix, Commet).

---

## Flavors

| Flavor | Components | RAM ceiling | Use case |
|--------|-----------|-------------|----------|
| **`minimal`** | Cilium + Kyverno + cert-manager + Vault + Kanidm + Headscale | ~2.3 GiB | Ultra-minimalist security substrate — edge nodes, CI, bootstrap |
| **`core`** | Full infra (no apps): all of the above + Tetragon + VictoriaMetrics/Logs + Mayastor + RustFS + CNPG + Registry + Web | ~4.8 GiB | Build-your-own-app on a hardened base |
| **`og`** *(default)* | Core + Stalwart (JMAP mail) + SimpleX Chat (metadata-free messaging) | ~6.3 GiB | Maximum privacy — self-hosted email, no-identifiers chat |
| **`matrix`** | Core + Tuwunel (Matrix homeserver) + Cinny (web UI) + LiveKit (E2EE voice/video) | ~6.4 GiB | Discord alternative with E2EE, OIDC-backed |
| **`commet`** | Core + Tuwunel + Commet (Flutter Matrix client) | ~6.0 GiB | Matrix with a modern Flutter UI |
| **`rust`** | Core + Stalwart + Tuwunel (both Rust) | ~6.0 GiB | Pure-Rust backend stack |

```bash
# Pick a flavor via env var
FLAVOR=rust     ./bootstrap.sh --dev
FLAVOR=minimal  ./bootstrap.sh --dev
FLAVOR=matrix   ./bootstrap.sh --dev

# Or via make
make deploy-rust
make deploy-minimal
```

---

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
│  VictoriaLogs — tamper-evident audit logging         │
├─────────────────────────────────────────────────────┤
│  Headscale — Tailscale-compatible mesh VPN           │
│  (only path into the cluster)                        │
├─────────────────────────────────────────────────────┤
│  ┌───────────────────────────────────────────────┐  │
│  │  Flavor Layer                                 │  │
│  │  • minimal: (none — security plane only)     │  │
│  │  • og: Stalwart + SimpleX                     │  │
│  │  • matrix: Tuwunel + Cinny + LiveKit          │  │
│  │  • rust: Stalwart + Tuwunel (both Rust)       │  │
│  └───────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────┤
│  PostgreSQL/CNPG + Registry + Web Dashboard + Backup │
└─────────────────────────────────────────────────────┘
```

---

## Quick start

### Option A — Existing Talos node

```bash
git clone <repo> && cd slam-stack
export CLUSTER_API_ENDPOINT="10.0.0.2:50000"

# Boot the node into Talos maintenance mode, then:
FLAVOR=rust ./bootstrap.sh --dev
```

### Option B — Automated Talos VM (libvirt)

The `tofu/modules/talos-vm/` module provisions libvirt VMs from a
factory.talos.dev image, with DHCP MAC→IP reservations, UEFI firmware,
and optional Secure Boot + TPM 2.0.

```bash
cd tofu/modules/talos-vm
cp examples/single-node.tfvars terraform.tfvars
tofu init && tofu apply               # VMs up in maintenance mode
cd ../..
make cluster CREATE_VMS=true          # apply config, bootstrap, Flux
```

### Verify

```bash
./verify.sh                  # security posture checks (live cluster)
./scripts/e2e-flux.sh        # pipeline checks (offline — no cluster)
```

---

## What gets installed

**Core (all flavors except `minimal`):**

1. Cilium — CNI + WireGuard + default-deny policies
2. Kyverno — admission control + Cosign image signing
3. Tetragon — eBPF runtime security
4. VictoriaLogs — immutable audit logging
5. VictoriaMetrics — metrics + alerting
6. Vault/OpenBao — dynamic secrets, PKI, TPM auto-unseal
7. cert-manager — TLS automation via Vault PKI
8. Mayastor — NVMe-oF block storage
9. CNPG + PostgreSQL — audited database
10. Registry — local container images
11. Kanidm — identity/OIDC, WebAuthn/Passkeys
12. Headscale — Tailscale-compatible mesh VPN
13. RustFS — WORM object storage
14. Web dashboard — OIDC-authenticated (Leptos + Axum)
15. Backup — encrypted CronJob

**Minimal flavor** ships a 6-component subset (Cilium, Kyverno,
cert-manager, Vault, Kanidm, Headscale) that fits in ~2 GiB. See
[`flavors/minimal/README.md`](flavors/minimal/README.md).

**Flavor apps** add the messaging/mail layer on top — see each
flavor's README for details.

---

## Repository layout

```
slam-stack/
├── talos/                  Talos machine configs (controlplane + worker)
├── components/             Core infra Kustomize components (shared)
│   ├── cilium/             CNI + WireGuard + network policies
│   ├── kyverno/            Admission control + image signature policy
│   ├── tetragon/           eBPF runtime security policies
│   ├── vault/              OpenBao install + dynamic secrets
│   ├── cert-manager/       TLS automation via Vault PKI
│   ├── victoria-logs/      Audit log aggregation
│   ├── victoria-metrics/   Metrics collection + alerting
│   ├── kanidm/             Identity provider (WebAuthn + OAuth2)
│   ├── mayastor/           NVMe-oF block storage
│   ├── rustfs/             WORM object storage (Rust)
│   ├── headscale/          Mesh VPN
│   ├── postgres/           CNPG-managed PostgreSQL
│   ├── kata/               MicroVM runtime class
│   ├── registry/           Local container registry
│   ├── backup/             Encrypted etcd backup CronJob
│   ├── web/                Dashboard (Leptos + Axum)
│   └── cosign/             Image signing keys
├── flavors/                Application flavor bundles
│   ├── minimal/            Empty bundle (security plane only)
│   ├── core/               (no flavor apps)
│   ├── og/                 Stalwart + SimpleX
│   ├── matrix/             Tuwunel + Cinny + LiveKit
│   ├── commet/             Tuwunel + Commet
│   └── rust/               Stalwart + Tuwunel (pure Rust)
├── clusters/               Flux cluster overlays
│   ├── common/             Shared Flux Kustomization CRDs
│   ├── phases/             Phase directories (00-sources → 04-services)
│   ├── minimal/            Reduced phase chain (sources → cni → platform → identity)
│   ├── base/               HelmRepository sources
│   ├── og/ matrix/ commet/ rust/ core/  Per-flavor Flux roots
├── workloads/              Reference workload examples
│   └── sample-rust-app/    axum web service, distroless, signed
├── tofu/                   OpenTofu — Talos + Flux bootstrap
│   ├── main.tf             Talos config apply + Flux bootstrap
│   ├── libvirt.tf          Optional compose of talos-vm module
│   └── modules/
│       └── talos-vm/       libvirt VM provisioner (the "Talos maker")
├── scripts/                Backup, verification, e2e tests
├── dev/                    Dev environment setup
├── web/                    Dashboard source (Rust)
├── bootstrap.sh            Full stack bootstrap
├── deploy.sh               Component deployer (FLAVOR-aware)
├── verify.sh               Security verification suite
├── Makefile                Flavor-aware convenience targets
├── SECURITY-MANIFESTO.md   Threat model and design principles
├── HARDWARE-GAPS.md        Physical items to acquire
├── RAM-OPTIONS.md          Memory budget analysis per flavor
└── runbook.md              Operations runbook
```

---

## Security posture

See [`SECURITY-MANIFESTO.md`](SECURITY-MANIFESTO.md) for the full threat
model and design principles. Key guarantees:

- ✅ No unsigned images can run (Cosign + Kyverno enforcement)
- ✅ No shell execution inside pods (Tetragon kills at kernel level)
- ✅ No pod-to-pod traffic without explicit policy (Cilium default-deny)
- ✅ No secrets on disk (Vault tmpfs, 15-minute rotation)
- ✅ No inbound ports (Headscale mesh only)
- ✅ No passwords (WebAuthn/Passkeys only, or TOTP per flavor)
- ✅ No unauthenticated dashboard access (OIDC via Kanidm)
- ✅ No static TLS certificates (cert-manager auto-rotation via Vault PKI)
- ✅ No default ServiceAccount tokens (Kyverno enforced)
- ✅ No blind spots (VictoriaMetrics alerting on OOM, crashes, security events)

---

## Resource budget (8 GB single node, 16 GB recommended)

| Flavor | Core RAM | + Apps | Total ceiling |
|--------|----------|--------|---------------|
| minimal | ~2.3 GiB | — | **~2.3 GiB** |
| core | ~2.4 GiB | — | **~4.8 GiB** |
| og | ~2.4 GiB | ~0.9 GiB (Stalwart + SimpleX) | **~6.3 GiB** |
| matrix | ~2.4 GiB | ~0.4 GiB (Tuwunel + Cinny + LiveKit) | **~6.4 GiB** |
| commet | ~2.4 GiB | ~0.2 GiB (Tuwunel + Commet) | **~6.0 GiB** |
| rust | ~2.4 GiB | ~0.2 GiB (Stalwart + Tuwunel) | **~6.0 GiB** |

See [`RAM-OPTIONS.md`](RAM-OPTIONS.md) for the per-component breakdown.

---

## IaC (OpenTofu / Terraform)

Two layers, composable:

1. **`tofu/modules/talos-vm/`** — provisions libvirt VMs from a
   factory.talos.dev image, with DHCP MAC→IP reservations, UEFI
   firmware, optional Secure Boot + TPM 2.0. Skip if you already have
   Talos nodes.
2. **`tofu/`** (root) — applies Talos machine config to the bootstrap
   node, bootstraps etcd, fetches kubeconfig, and bootstraps Flux
   against the chosen cluster overlay.

```bash
# Plan (existing node)
make tofu-plan NODE_IP=192.168.1.100 FLAVOR=rust

# Plan (spin up VMs first)
make tofu-plan CREATE_VMS=true FLAVOR=minimal

# Apply
make cluster NODE_IP=192.168.1.100 FLAVOR=rust
```

See [`tofu/modules/talos-vm/README.md`](tofu/modules/talos-vm/README.md)
for the libvirt module docs.

---

## Reference workload

[`workloads/sample-rust-app/`](workloads/sample-rust-app/) is a minimal
axum web service demonstrating how to deploy your own app on the
platform. It inherits every security property:

- WireGuard-encrypted pod traffic
- Cosign-signed image, verified by Kyverno at admission
- Read-only rootfs, non-root user, all caps dropped, seccomp RuntimeDefault
- Default-deny network policy with explicit Headscale-only ingress
- Resource limits enforced by Kyverno

Copy and adapt for your own workloads.

---

## Verification

Two e2e suites:

```bash
# Pipeline check (offline — validates Flux Kustomize builds, dependency
# chains, signature enforcement, policy coverage). Runs in CI without
# a cluster.
./scripts/e2e-flux.sh

# Live cluster check (requires a deployed matrix flavor)
./scripts/e2e-matrix.sh
```

The offline suite covers all six flavors — kustomize build, dependency
chain integrity, HelmRepository references, signature key match,
phase content validation.

---

## License

Private repository. All rights reserved.
