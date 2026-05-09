//! OIDC authentication via Kanidm
#![cfg(feature = "ssr")]

use crate::models::UserIdentity;
use openidconnect::core::{CoreAuthenticationFlow, CoreClient, CoreProviderMetadata};
use openidconnect::reqwest::async_http_client;
use openidconnect::{
    AuthorizationCode, ClientId, ClientSecret, CsrfToken, IssuerUrl, Nonce,
    PkceCodeChallenge, PkceCodeVerifier, RedirectUrl, Scope,
};
use openidconnect::TokenResponse;
use std::collections::HashMap;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;

const AUTH_TIMEOUT: Duration = Duration::from_secs(300);
const SESSION_TTL: Duration = Duration::from_secs(8 * 3600);

struct PendingAuth {
    verifier: PkceCodeVerifier,
    nonce: Nonce,
    created: Instant,
}

struct Session {
    user: UserIdentity,
    expires_at: Instant,
}

pub struct OidcState {
    client: CoreClient,
    pending: Mutex<HashMap<String, PendingAuth>>,
    sessions: Mutex<HashMap<String, Session>>,
}

fn random_token() -> String {
    let mut buf = [0u8; 32];
    getrandom::getrandom(&mut buf).expect("rng failure");
    buf.iter().map(|b| format!("{:02x}", b)).collect()
}

pub fn extract_session_token(cookie_header: &str) -> Option<String> {
    cookie_header
        .split(';')
        .map(|s| s.trim())
        .find(|s| s.starts_with("slam_session="))
        .and_then(|s| s.strip_prefix("slam_session=").map(str::to_string))
}

impl OidcState {
    pub async fn init(
        issuer_url: &str,
        client_id: &str,
        client_secret: &str,
        redirect_url: &str,
    ) -> Result<Self, String> {
        let issuer = IssuerUrl::new(issuer_url.to_string()).map_err(|e| e.to_string())?;
        let metadata = CoreProviderMetadata::discover_async(issuer, async_http_client)
            .await
            .map_err(|e| format!("OIDC discovery failed: {e}"))?;

        let client = CoreClient::from_provider_metadata(
            metadata,
            ClientId::new(client_id.to_string()),
            Some(ClientSecret::new(client_secret.to_string())),
        )
        .set_redirect_uri(
            RedirectUrl::new(redirect_url.to_string()).map_err(|e| e.to_string())?,
        );

        Ok(Self {
            client,
            pending: Mutex::new(HashMap::new()),
            sessions: Mutex::new(HashMap::new()),
        })
    }

    pub async fn start_auth(&self) -> String {
        let (pkce_challenge, pkce_verifier) = PkceCodeChallenge::new_random_sha256();

        let (auth_url, csrf_token, nonce) = self
            .client
            .authorize_url(
                CoreAuthenticationFlow::AuthorizationCode,
                CsrfToken::new_random,
                Nonce::new_random,
            )
            .add_scope(Scope::new("openid".into()))
            .add_scope(Scope::new("profile".into()))
            .add_scope(Scope::new("email".into()))
            .set_pkce_challenge(pkce_challenge)
            .url();

        let state_key = csrf_token.secret().clone();
        let mut map = self.pending.lock().await;
        map.retain(|_, v| v.created.elapsed() < AUTH_TIMEOUT);
        map.insert(
            state_key,
            PendingAuth {
                verifier: pkce_verifier,
                nonce,
                created: Instant::now(),
            },
        );

        auth_url.to_string()
    }

    pub async fn exchange(&self, code: &str, state: &str) -> Result<String, String> {
        let auth = self
            .pending
            .lock()
            .await
            .remove(state)
            .ok_or("No pending auth (expired or invalid)")?;

        if auth.created.elapsed() > AUTH_TIMEOUT {
            return Err("Auth request expired".into());
        }

        let tokens = self
            .client
            .exchange_code(AuthorizationCode::new(code.into()))
            .set_pkce_verifier(auth.verifier)
            .request_async(async_http_client)
            .await
            .map_err(|e| format!("Token exchange failed: {e}"))?;

        let id_token = tokens.id_token().ok_or("No ID token")?;
        let claims = id_token
            .claims(&self.client.id_token_verifier(), &auth.nonce)
            .map_err(|e| format!("ID token verification failed: {e}"))?;

        let user = UserIdentity {
            subject: claims.subject().to_string(),
            email: claims.email().map(|e| e.to_string()).unwrap_or_default(),
            name: claims
                .name()
                .and_then(|n| n.get(None).map(|s| s.to_string()))
                .unwrap_or_else(|| claims.subject().to_string()),
        };

        let token = random_token();
        let mut sessions = self.sessions.lock().await;
        sessions.retain(|_, v| v.expires_at > Instant::now());
        sessions.insert(
            token.clone(),
            Session {
                user,
                expires_at: Instant::now() + SESSION_TTL,
            },
        );

        Ok(token)
    }

    pub async fn get_user(&self, token: &str) -> Option<UserIdentity> {
        let mut sessions = self.sessions.lock().await;
        if let Some(session) = sessions.get(token) {
            if session.expires_at > Instant::now() {
                return Some(session.user.clone());
            }
            sessions.remove(token);
        }
        None
    }
}
