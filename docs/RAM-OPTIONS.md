# RAM Options — Matrix Flavor

Baseline: Talos single-node, 4GB RAM minimum viable.

## Tiers

### Bare Minimum — ~1.4Gi at limits
Cilium + Tuwunel + Kanidm + Cinny. Just enough to chat.

| Component | Request | Limit | Notes |
|-----------|---------|-------|-------|
| Cilium agent | 256Mi | 512Mi | CNI, required |
| Cilium operator | 128Mi | 256Mi | Can reduce to 1 replica |
| Tuwunel | 128Mi | 256Mi | Tightened from 512Mi |
| Kanidm | 128Mi | 256Mi | IDP for OIDC |
| Cinny | 32Mi | 64Mi | Static nginx, tightened from 128Mi |

### + Security — +0.8Gi = 2.2Gi
Kyverno admission control + Tetragon eBPF runtime security.

| Component | Request | Limit | Notes |
|-----------|---------|-------|-------|
| Kyverno | 128Mi | 512Mi | Image signing, pod security |
| Tetragon | 128Mi | 512Mi | Kernel-level enforcement |
| Tetragon operator | 64Mi | 256Mi | |

### + Voice/Video — +1.1Gi = 3.3Gi
LiveKit SFU for calls.

| Component | Request | Limit | Notes |
|-----------|---------|-------|-------|
| LiveKit | 256Mi | 1Gi | The heaviest single component |
| LiveKit Redis | 32Mi | 128Mi | Session state |

### + Observability — +0.6Gi = 3.9Gi
Metrics + audit log pipeline.

| Component | Request | Limit | Notes |
|-----------|---------|-------|-------|
| VictoriaMetrics | 128Mi | 256Mi | Metrics storage |
| VictoriaLogs | 256Mi | 384Mi | Audit log sink |

### + Full Stack — 5.8Gi
Everything above plus Vault, Headscale, web dashboard, cert-manager.

## Components You Can Drop on Single-Node

| Component | RAM Saved | Why |
|-----------|-----------|-----|
| Mayastor | ~2Gi | Use local-path-provisioner instead |
| CNPG (Postgres) | 384Mi | Tuwunel uses RocksDB, no Postgres needed |
| Vault | 512Mi | Only needed for dynamic secrets rotation |
| Cert-manager | 256Mi | Self-signed or manual certs work for internal |
| Headscale | 256Mi | Only if not using Tailscale/Funnel for access |
| Web dashboard | 128Mi | CLI-only management |

## Recommendations

- **4GB node**: Bare minimum tier. Drop Mayastor, CNPG, Vault, observability. Tighten all limits.
- **8GB node**: +Security tier comfortably. Add observability if you want audit trail.
- **16GB node**: Full stack with headroom.
