# Sample Rust Workload

Reference application showing how to deploy a Rust service on
slam-stack. Inherits every security property of the platform:

- ✅ WireGuard-encrypted pod traffic (Cilium)
- ✅ Image signature verification (Cosign + Kyverno)
- ✅ Read-only root filesystem, non-root user, no caps
- ✅ Default-deny network policy, explicit allow-list
- ✅ Resource limits enforced by Kyverno admission
- ✅ Pod Security Standards: restricted

## Layout

```
sample-rust-app/
├── Cargo.toml          # axum 0.7 + tokio + serde
├── Cargo.lock
├── Dockerfile          # cargo-chef + distroless (~15 MB image)
├── src/main.rs         # /healthz, /api/v1/hello, /api/v1/echo
└── manifests/
    ├── kustomization.yaml
    ├── namespace.yaml          # pod-security=restricted
    ├── serviceaccount.yaml     # no automounted token
    ├── deployment.yaml         # probes, securityContext, resources
    ├── service.yaml
    └── networkpolicy.yaml      # Headscale-only ingress
```

## Build & deploy

```bash
# Build and push to the slam-stack local registry
docker build -t registry.registry.svc.cluster.local:5000/sample-rust-app:0.1.0 .
docker push registry.registry.svc.cluster.local:5000/sample-rust-app:0.1.0

# Sign the image (Kyverno will reject unsigned)
cosign sign --key components/cosign/cosign.key \
  registry.registry.svc.cluster.local:5000/sample-rust-app:0.1.0

# Deploy
kubectl apply -k workloads/sample-rust-app/manifests/

# Verify
kubectl -n sample-app port-forward svc/sample-rust-app 8080:8080
curl http://localhost:8080/healthz          # → ok
curl http://localhost:8080/api/v1/hello?name=Rust
# → {"message":"Hello, Rust!","server":"sample-rust-app/0.1.0","version":"0.1.0"}
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/healthz` | Liveness/readiness probe target |
| GET | `/api/v1/hello?name=Foo` | Greeting |
| POST | `/api/v1/echo` | JSON echo with timestamp |

## Adapt for your own workload

1. Copy this directory: `cp -r workloads/sample-rust-app workloads/my-app`
2. Edit `Cargo.toml`, `src/main.rs`, image tag in `deployment.yaml`
3. Update the CiliumNetworkPolicy to allow your required egress
4. Build, sign, deploy.
