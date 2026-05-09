//! Axum auth middleware — redirects to /login if no valid session
#![cfg(feature = "ssr")]

use axum::extract::Request;
use axum::http::header::COOKIE;
use axum::middleware::Next;
use axum::response::{IntoResponse, Redirect, Response};
use std::sync::Arc;

use crate::auth::{extract_session_token, OidcState};

static PUBLIC_PATHS: &[&str] = &["/login", "/auth/redirect", "/auth/callback"];

pub async fn auth_middleware(
    axum::Extension(state): axum::Extension<Arc<OidcState>>,
    mut request: Request,
    next: Next,
) -> Response {
    let path = request.uri().path();

    if PUBLIC_PATHS.iter().any(|p| path == *p)
        || path.starts_with("/pkg/")
        || path.starts_with("/favicon")
    {
        return next.run(request).await;
    }

    let token = request
        .headers()
        .get(COOKIE)
        .and_then(|v| v.to_str().ok())
        .and_then(extract_session_token);

    match token {
        Some(t) if !t.is_empty() => match state.get_user(&t).await {
            Some(user) => {
                request.extensions_mut().insert(user);
                next.run(request).await
            }
            None => Redirect::to("/login").into_response(),
        },
        _ => Redirect::to("/login").into_response(),
    }
}
