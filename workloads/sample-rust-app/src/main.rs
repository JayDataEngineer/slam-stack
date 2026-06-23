//! Sample Rust workload — reference deployment on slam-stack.
//!
//! Demonstrates the security posture every workload inherits:
//!   - WireGuard-encrypted pod traffic (Cilium)
//!   - Image signature verification (Cosign + Kyverno)
//!   - Read-only root filesystem + non-root user
//!   - OIDC-authenticated endpoints (via Kanidm / Headscale)
//!
//! Build: cargo build --release
//! Run:   ./target/release/sample-rust-app
//! Health: GET /healthz  → 200 "ok"
//! Greet:  GET /api/v1/hello?name=Rust → 200 {"message":"Hello, Rust!"}

use axum::{
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;

#[derive(Serialize)]
struct HelloResponse {
    message: String,
    server: &'static str,
    version: &'static str,
}

#[derive(Deserialize)]
struct HelloRequest {
    name: Option<String>,
}

async fn healthz() -> &'static str {
    "ok"
}

async fn hello(Query(req): Query<HelloRequest>) -> Json<HelloResponse> {
    let name = req.name.unwrap_or_else(|| "world".to_string());
    Json(HelloResponse {
        message: format!("Hello, {}!", name),
        server: "sample-rust-app/0.1.0",
        version: env!("CARGO_PKG_VERSION"),
    })
}

#[derive(Serialize)]
struct EchoResponse {
    echoed: serde_json::Value,
    received_at: String,
}

async fn echo(Json(body): Json<serde_json::Value>) -> Json<EchoResponse> {
    Json(EchoResponse {
        echoed: body,
        received_at: chrono::Utc::now().to_rfc3339(),
    })
}

use axum::extract::Query;

#[tokio::main]
async fn main() {
    let addr = std::env::var("LISTEN_ADDR").unwrap_or_else(|_| "0.0.0.0:8080".into());
    let addr: SocketAddr = addr.parse().expect("valid LISTEN_ADDR");

    let app = Router::new()
        .route("/healthz", get(healthz))
        .route("/api/v1/hello", get(hello))
        .route("/api/v1/echo", post(echo));

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    tracing::info!("listening on {addr}");
    axum::serve(listener, app).await.unwrap();
}
