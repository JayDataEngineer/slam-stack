# Slam Stack — Minimal Flavor

**Ultra-minimal secure Kubernetes platform.** Drops every component that
isn't part of the zero-trust security plane — no storage, no database,
no registry, no observability stack, no apps. Just the security substrate.

Fits in **~1 GB RAM** alongside Talos.

## What's included

| Component | Purpose | Mem Limit |
|-----------|---------|-----------|
| **Cilium** | CNI + WireGuard encryption + default-deny network policy | 512 Mi |
| **Kyverno** | Admission control + Cosign image signature enforcement | 512 Mi |
| **cert-manager** | TLS automation via Vault PKI | 256 Mi |
| **OpenBao/Vault** | Dynamic secrets + transit encryption + PKI | 512 Mi |
| **Kanidm** | OIDC identity provider (WebAuthn / Passkeys) | 256 Mi |
| **Headscale** | Tailscale-compatible mesh VPN (only path in) | 256 Mi |
| **Total** | | **~2.3 Gi** |

## What's deliberately excluded

- ❌ Mayastor / RustFS (no persistent storage — workloads must be stateless)
- ❌ PostgreSQL / CNPG (no database)
- ❌ Tetragon (no eBPF runtime enforcement — Kyverno admission only)
- ❌ VictoriaMetrics / VictoriaLogs (no metrics / log aggregation)
- ❌ Local registry (no air-gapped operation)
- ❌ Backup CronJob (nothing to back up)
- ❌ Web dashboard (no UI)
- ❌ Kata microVM (no extra isolation layer)

## Use cases

- **Edge nodes** with severe RAM constraints (<4 GB total)
- **Bootstrap cluster** — bring up security plane first, add apps later
- **CI test bed** for verifying the security substrate in isolation
- **Minimal attack surface** deployments where less is more

## Deploy

```bash
FLAVOR=minimal ./deploy.sh
```

Or via Flux GitOps:

```bash
flux bootstrap ... --path=./clusters/minimal
```
