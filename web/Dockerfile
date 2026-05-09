# Stage 1: Build the Rust backend and WASM frontend
FROM rust:1.85 AS builder

RUN cargo install cargo-leptos --locked

WORKDIR /build
COPY Cargo.toml Cargo.lock* ./
COPY src ./src
COPY index.html index.html
COPY style ./style

# Build with SSR
RUN cargo leptos build --release -vv

# Stage 2: Minimal runtime image
FROM gcr.io/distroless/cc-debian12:latest

COPY --from=builder /build/target/release/slam-stack-web /usr/local/bin/slam-stack-web
COPY --from=builder /build/target/site /usr/local/share/slam-stack-web

ENV LEPTOS_SITE_ROOT=/usr/local/share/slam-stack-web
ENV LEPTOS_SITE_ADDR=0.0.0.0:8080
ENV LEPTOS_OUTPUT_NAME=slam-stack-web

EXPOSE 8080

USER 10000:10000

ENTRYPOINT ["/usr/local/bin/slam-stack-web"]
