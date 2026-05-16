# Slam Stack Runbook

## What is Slam Stack?

An **extreme-security, zero-trust, defense-in-depth** Kubernetes cluster built on
Talos Linux. Light enough to run on 4-8GB RAM while achieving military-grade
security posture — "slam it on a table and you're good to go."

## Architecture (Corrected)

```
┌──────────────────────────────────────────────────────────┐
│                    Talos Linux (Immutable)                │
│  ┌────────────────────────────────────────────────────┐  │
│  │              Kata / Cloud Hypervisor (opt)          │  │
│  │  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────────┐  │  │
│  │  │App A │ │App B │ │Kanidm│ │Vault │ │Flavor App│  │  │
│  │  │      │ │      │ │      │ │      │ │(OG/Matrix)│  │  │
│  │  └──┬───┘ └──┬───┘ └──┬───┘ └──┬───┘ └────┬─────┘  │  │
│  │     │         │        │        │          │         │  │
│  │  ┌──┴─────────┴────────┴────────┴──────────┴──┐      │  │
│  │  │  Cilium (eBPF + WireGuard + CiliumIdentity) │      │  │
│  │  │  · Kernel-level WireGuard encryption         │      │  │
│  │  │  · Label-based identity (not SPIFFE —        │      │  │
│  │  │    SPIRE mTLS is beta + conflicts with WG)   │      │  │
│  │  │  · Default deny (microsegmentation)          │      │  │
│  │  └─────────────────────────────────────────────┘      │  │
│  │  ┌─────────────────────────────────────────────┐      │  │
│  │  │        Tetragon (eBPF Runtime)               │     │  │
│  │  │  · Kills malicious syscalls at kernel level  │      │  │
│  │  │  · Blocks shell, mount, packet tools         │      │  │
│  │  └─────────────────────────────────────────────┘      │  │
│  │  ┌─────────────────────────────────────────────┐      │  │
│  │  │        Kyverno + Cosign (Admission)          │     │  │
│  │  │  · Only signed images run                     │      │  │
│  │  │  · No privileged containers                   │      │  │
│  │  │  · Read-only rootfs + non-root enforced      │      │  │
│  │  └─────────────────────────────────────────────┘      │  │
│  │  ┌─────────────────────────────────────────────┐      │  │
│  │  │        Mayastor (Block) + RustFS (Object)   │      │  │
│  │  │  · NVMe-oF via SPDK (Rust)                   │      │  │
│  │  │  · WORM-compatible object locking            │      │  │
│  │  └─────────────────────────────────────────────┘      │  │
│  └────────────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────────────┐  │
│  │        Headscale / Cloudflare Tunnel               │  │
│  │  · Zero inbound ports, outbound-only mesh          │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

## Architecture Decisions

### Why WireGuard + CiliumIdentity instead of SPIRE mTLS?

**Research finding:** Cilium's mutual authentication with SPIRE is currently
**BETA** (as of May 2026) and has critical limitations:
- Cannot run simultaneously with WireGuard encryption
- No UDP support
- No cross-cluster support
- No custom CA support

**Decision:** Use **WireGuard encryption** (stable, kernel-level) + **Cilium native
security identity** (label-based) instead. This gives us:
- Kernel-level encryption for all pod-to-pod traffic
- Identity-aware network policies (CiliumIdentity)
- No beta features
- Lower resource overhead (no SPIRE server/agent)

The threat model is still covered: encrypted at kernel level, identity-verified
at the policy level, with Tetragon handling runtime process enforcement.

### Why Kata/CLH instead of Firecracker?

**Research finding:** Talos's official `kata-containers` extension ships with
**Cloud Hypervisor**, not Firecracker. Firecracker support was deferred upstream
to keep extension image size small. Cloud Hypervisor is also written in Rust and
provides equivalent KVM-based microVM isolation.

For dev: skip microVMs entirely (standard runc is fine for development).
For prod: enable Kata with Cloud Hypervisor via the Image Factory schematic.

### Why raw manifests instead of Helm for some tools?

| Tool | Chart status | Decision |
|------|-------------|----------|
| Kanidm | No official chart | Raw K8s manifests |
| Stalwart (OG) | No official chart | Raw K8s manifests |
| Headscale | Community chart: gabe565/headscale | Helm |
| OpenBao | Official chart | Helm |
| SurrealDB | Official chart | Helm |
| VictoriaLogs | Official chart | Helm |
| RustFS | In-source chart only | Raw K8s manifests |
| Cilium | Official chart | Helm |
| Kyverno | Official chart | Helm |
| Tetragon | Official chart | Helm |

## Components

### Core Infrastructure
| Component | Language | Role | RAM |
|-----------|----------|------|-----|
| Talos Linux | Go | Immutable K8s OS | ~800MB |
| Cloud Hypervisor | Rust | MicroVM isolation (opt-in) | ~5MiB each |
| Cilium | C/Go/Rust | eBPF networking + WireGuard | ~300MB |
| Tetragon | C/Go | Kernel-level runtime security | ~200MB |
| Kyverno | Go | Admission control | ~150MB |
| Cosign | Go | Image signing | ~50MB |

### Services
| Component | Language | Role | RAM | Deploy method |
|-----------|----------|------|-----|--------------|
| Kanidm | Rust | Identity / SSO / Passkeys | ~80MB | Raw manifests |
| OpenBao | Go | Secrets / PKI / Dynamic creds | ~300MB | Helm |
| SurrealDB | Rust | Multi-model database | ~300MB | Helm |
| Stalwart (OG) | Rust | Mail server (SMTP+JMAP) | ~150MB | Raw manifests |
| RustFS | Rust | S3 object storage (WORM) | ~300MB | Raw manifests |
| VictoriaLogs | Go | Immutable audit logging | ~200MB | Helm |
| Headscale | Go | Mesh VPN (zero inbound) | ~50MB | Helm (community) |

### Total Baseline: ~2.8GB (room for user apps on 4-8GB hardware)

## Security Layers

### Layer 1: Hardware Root of Trust (TPM)
- Disk encryption tied to physical TPM 2.0 chip
- Server cannot boot if SSD is removed

### Layer 2: Immutable OS (Talos)
- No SSH, no shell, no package manager
- API-only management via mTLS (~12 binaries total)

### Layer 3: MicroVM Isolation (Kata/CLH, optional)
- Every pod can run in its own lightweight KVM microVM
- Add `runtimeClassName: kata` to any pod spec
- Uses Cloud Hypervisor (Rust) — not Firecracker

### Layer 4: Supply Chain Security (Kyverno + Cosign)
- Only cryptographically signed images execute
- Private signing key on YubiKey
- Enforced: non-root, read-only rootfs, no priv esc, no host network

### Layer 5: Network Zero-Trust (Cilium)
- Default deny: nothing talks without explicit policy
- WireGuard kernel-level encryption for all pod traffic
- Identity-based (Cilium labels), not IP-based
- Per-service egress rules — apps cannot reach the internet unless allowed

### Layer 6: Runtime Enforcement (Tetragon)
- eBPF syscall monitoring: kills shells, packet tools, mount commands
- Blocks SUID exploitation, crypto miners

### Layer 7: Credential Hygiene (Vault)
- Dynamic secrets: DB passwords rotate every 15 minutes
- PKI: internal mTLS certs valid 24 hours
- Full audit trail to VictoriaLogs

## Setup

### Prerequisites
- Ubuntu machine with 16GB+ RAM (for dev QEMU VMs)
- Bare metal or VM with TPM 2.0 (for prod)
- YubiKey for Cosign signing + Talos mTLS

### Dev (Talos VM on Ubuntu)
```bash
# 1. Create the Talos VM cluster
cd slam-stack
chmod +x dev/setup.sh deploy.sh verify.sh
./dev/setup.sh

# 2. Deploy components
export KUBECONFIG=~/.kube/slam-stack-config
./deploy.sh --dev

# 3. Verify
./verify.sh
```

### Production (Bare Metal)
```bash
# 1. Generate custom Talos image with Kata extension
#    (see talos/patches/kata.yaml for schematic)

# 2. Boot hardware with Talos image
# 3. Apply configs:
talosctl apply-config --file talos/controlplane.yaml
talosctl apply-config --file talos/worker.yaml

# 4. Bootstrap
talosctl bootstrap
export KUBECONFIG=~/.kube/slam-stack-config

# 5. Set up GitOps
kubectl apply -f components/flux/bootstrap.yaml
flux bootstrap git --url=https://github.com/yourorg/slam-stack \
  --path=./clusters/prod

# 6. Verify
./verify.sh
```

## Day-0 Ceremony

### 1. Generate Cosign Keypair (Airgapped Machine)
```bash
cd components/cosign
chmod +x setup.sh
./setup.sh
# Save cosign.key to YubiKey PIV slot
# DELETE cosign.key from disk after saving to YubiKey
```

### 2. Initialize Vault
```bash
kubectl exec -n vault deploy/vault -- vault operator init \
  -key-shares=1 -key-threshold=1 -format=json > vault-keys.json
kubectl exec -n vault deploy/vault -- vault operator unseal \
  $(cat vault-keys.json | jq -r '.unseal_keys_b64[0]')
# Store unseal key in TPM (prod) or password manager (dev)
```

### 3. Configure Vault PKI + Dynamic Secrets
```bash
kubectl apply -f components/vault/dynamic-secrets.yaml
kubectl exec -n vault deploy/vault -- /bin/sh -c "$(kubectl get configmap vault-pki-setup -n vault -o jsonpath='{.data.setup\.sh}')"
kubectl exec -n vault deploy/vault -- /bin/sh -c "$(kubectl get configmap vault-db-setup -n vault -o jsonpath='{.data.setup\.sh}')"
```

### 4. Setup Kanidm
```bash
# Create admin account (passkey only, no password)
kubectl exec -n identity deploy/kanidm -- kanidm login --name admin
# Enforce WebAuthn for all users
kubectl exec -n identity deploy/kanidm -- kanidm person credential set-passkey admin
```

**Flavor-specific Kanidm setup:**

For the Matrix flavor (password + TOTP via Aegis):
```bash
kubectl exec -n identity deploy/kanidm -- kanidm person create <name> <display>
kubectl exec -n identity deploy/kanidm -- kanidm person credential set-password <name>
kubectl exec -n identity deploy/kanidm -- kanidm person credential set-totp <name>
```

For the OG flavor (passkey-only, maximum security):
```bash
kubectl exec -n identity deploy/kanidm -- kanidm person create <name> <display>
kubectl exec -n identity deploy/kanidm -- kanidm person credential set-passkey <name>
```

### 5. Sign Your Images
```bash
cosign sign --key cosign.key ghcr.io/yourorg/yourapp:latest
```

### 6. Register Devices on Headscale
```bash
kubectl exec -n network deploy/headscale -- headscale users create slam-stack
kubectl exec -n network deploy/headscale -- headscale preauthkeys create -e 24h -u slam-stack
# Use the returned key on your laptop to join the mesh
```

## Network Map

```
Ingress (Headscale mesh / Cloudflare Tunnel)
  │
  ├── Kanidm :443      (OIDC provider, passkey/TOTP auth)
  ├── Vault  :8200     (secrets, PKI, dynamic creds)
  ├── VictoriaLogs :8480 (audit log ingestion)
  │
  └── Flavor-specific services:
      ├── OG: Stalwart :443 (JMAP), :465 (SMTP)
      ├── OG: SimpleX SMP :5223 (message relay)
      ├── OG: SimpleX XFTP :443 (file relay)
      ├── Matrix: Continuwuity :443 (Matrix homeserver)
      ├── Matrix: Cinny :8080 (web UI)
      └── Matrix: LiveKit :7880 (E2EE voice/video)

Internal flows only (no internet):
  Tetragon ──► VictoriaLogs (audit events)
  Vault     ──► VictoriaLogs (audit log stream)
  Kanidm    ──► VictoriaLogs (audit log stream)
  All apps  ──► Kanidm (OIDC authentication)
  All apps  ──► Vault (secret injection)

Default deny:
  Apps CANNOT talk to each other without explicit CiliumNetworkPolicy
  Apps CANNOT reach the internet without explicit egress rule
```

## Security Drills

### Scenario: Container escape detected
```
1. Tetragon kills the process (kernel-level SIGKILL)
2. Cilium blocks lateral movement (default-deny)
3. Read-only rootfs prevents file persistence
4. Vault revokes credentials for that identity
5. VictoriaLogs has immutable record
```

### Scenario: Rogue image pushed to cluster
```
1. Kyverno rejects the pod — image not signed by Cosign key
2. Admission webhook returns "image signature verification failed"
3. No pod is created; no impact
```

### Scenario: Admin laptop stolen
```
1. YubiKey PIV prevents talosctl access
2. Headscale session can be revoked from another device
3. Vault tokens expire within 30 minutes
4. Cluster is inaccessible without physical YubiKey
```

## Maintenance

```bash
# Update Talos
talosctl upgrade --image ghcr.io/siderolabs/installer:v1.13.0

# Update Cilium (no downtime expected)
helm upgrade cilium cilium/cilium -n kube-system -f components/cilium/install.yaml

# Rotate Vault keys
kubectl exec -n vault deploy/vault -- vault operator rekey

# Backup etcd
./scripts/backup-etcd.sh

# Check cluster health
talosctl health
kubectl get pods -A | grep -v Running

# View Tetragon events
kubectl logs -n kube-system -l app.kubernetes.io/name=tetragon

# Check Kyverno policy reports
kubectl get policyreports -A

# Full security posture check
./verify.sh
```

## Known Gaps / Future Work

- [ ] Cross-cluster / multi-region HA (3+ controlplanes)
- [ ] Firecracker microVM support (pending upstream Talos extension)
- [ ] Cilium mTLS with SPIRE (waiting for stable release + WireGuard compat)
- [ ] Automated X.509 cert rotation via cert-manager
- [ ] Full GitOps migration (Flux bootstrap is skeleton)
- [ ] Automated Vault unseal via TPM (requires physical hardware)
- [ ] Load testing (how many auth requests can Kanidm handle?)
