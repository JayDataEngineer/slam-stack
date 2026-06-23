# Slam Stack — Rust Flavor

**Pure-Rust backend stack.** Every server-side component in this flavor is
written in Rust, demonstrating an end-to-end Rust deployment on top of the
slam-stack security platform.

## Components

| Component | Language | Purpose |
|-----------|----------|---------|
| **Stalwart Mail** | Rust | SMTP + JMAP mail server (no IMAP) |
| **Tuwunel** | Rust | Matrix homeserver (Continuwuity fork) |
| Kanidm (core) | Rust | OIDC / WebAuthn identity provider |
| RustFS (core) | Rust | S3-compatible object storage |
| Slam Stack Web (core) | Rust (Leptos + Axum) | OIDC-authenticated dashboard |

## Why Rust

- **Memory safety** without GC pauses → predictable latency for mail and chat
- **Small binaries** → smaller attack surface, faster cold-start
- **No runtime** → distroless images viable (`gcr.io/distroless/cc-debian12`)
- **WASM-friendly** → Leptos dashboard compiles to WASM for the client side

## Deploy

```bash
FLAVOR=rust ./deploy.sh
```

Or via Flux GitOps:

```bash
flux bootstrap ... --path=./clusters/rust
```

## Verification

```bash
FLAVOR=rust ./verify.sh
```
