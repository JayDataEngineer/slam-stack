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

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Unit tests — exercise handler logic without network I/O.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use http_body_util::BodyExt;
    use tower::ServiceExt;

    fn test_app() -> Router {
        Router::new()
            .route("/healthz", get(healthz))
            .route("/api/v1/hello", get(hello))
            .route("/api/v1/echo", post(echo))
    }

    #[tokio::test]
    async fn healthz_returns_200_ok() {
        let resp = test_app()
            .oneshot(Request::builder().uri("/healthz").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        let body = resp.into_body().collect().await.unwrap().to_bytes();
        assert_eq!(&body[..], b"ok");
    }

    #[tokio::test]
    async fn hello_with_name_returns_personalized_greeting() {
        let resp = test_app()
            .oneshot(
                Request::builder()
                    .uri("/api/v1/hello?name=Rust")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        let body = resp.into_body().collect().await.unwrap().to_bytes();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["message"], "Hello, Rust!");
    }

    #[tokio::test]
    async fn hello_without_name_defaults_to_world() {
        let resp = test_app()
            .oneshot(
                Request::builder()
                    .uri("/api/v1/hello")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        let body = resp.into_body().collect().await.unwrap().to_bytes();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["message"], "Hello, world!");
    }

    #[tokio::test]
    async fn echo_round_trips_json_body() {
        let payload = r#"{"key":"value","nested":{"num":42}}"#;
        let resp = test_app()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/v1/echo")
                    .header("content-type", "application/json")
                    .body(Body::from(payload))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        let body = resp.into_body().collect().await.unwrap().to_bytes();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["echoed"]["key"], "value");
        assert_eq!(json["echoed"]["nested"]["num"], 42);
        assert!(json["received_at"].as_str().unwrap().contains('T'));
    }

    #[tokio::test]
    async fn unknown_route_returns_404() {
        let resp = test_app()
            .oneshot(
                Request::builder()
                    .uri("/api/v1/nonexistent")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
    }
}
