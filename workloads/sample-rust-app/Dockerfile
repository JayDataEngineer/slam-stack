# syntax=docker/dockerfile:1.7
# Sample Rust workload — multi-stage build, distroless runtime.
# Resulting image is ~15 MB and runs as nobody:nogroup with a read-only rootfs.

# ─── Stage 1: cargo-chef platter (caches deps) ──────────────────────────
FROM rust:1.85 AS chef
RUN cargo install cargo-chef --locked --root /usr/local/cargo
WORKDIR /app

FROM chef AS planner
COPY Cargo.toml Cargo.lock ./
RUN cargo chef prepare --recipe-path recipe.json

# ─── Stage 2: build dependencies + app ──────────────────────────────────
FROM chef AS builder
COPY --from=planner /app/recipe.json recipe.json
RUN cargo chef cook --release --recipe-path recipe.json
COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN cargo build --release --bin sample-rust-app

# ─── Stage 3: distroless runtime ────────────────────────────────────────
FROM gcr.io/distroless/cc-debian12:latest
COPY --from=builder /app/target/release/sample-rust-app /usr/local/bin/sample-rust-app
ENV LISTEN_ADDR=0.0.0.0:8080
EXPOSE 8080
USER nobody:nogroup
ENTRYPOINT ["/usr/local/bin/sample-rust-app"]
