#[cfg(feature = "ssr")]
#[tokio::main]
async fn main() {
    use axum::Router;
    use axum::routing::get;
    use leptos::prelude::*;
    use leptos_axum::{generate_route_list, LeptosRoutes};
    use std::sync::Arc;

    // Initialize SurrealDB connection
    let db_url = std::env::var("SURREALDB_URL")
        .unwrap_or_else(|_| "http://surrealdb.database.svc.cluster.local:8000".into());
    let db_ns = std::env::var("SURREALDB_NS").unwrap_or_else(|_| "slamstack".into());
    let db_name = std::env::var("SURREALDB_DB").unwrap_or_else(|_| "dashboard".into());
    let db_user = std::env::var("SURREALDB_USER").unwrap_or_else(|_| "root".into());
    let db_pass = std::env::var("SURREALDB_PASS").unwrap_or_else(|_| "root".into());

    match slam_stack_web::state::init(&db_url, &db_ns, &db_name, &db_user, &db_pass).await {
        Ok(()) => eprintln!("Connected to SurrealDB at {db_url}"),
        Err(e) => eprintln!("WARNING: SurrealDB connection failed: {e} — incident CRUD will fail"),
    }

    let conf = get_configuration(Some("Cargo.toml")).unwrap();
    let leptos_options = conf.leptos_options;
    let addr = leptos_options.site_addr;
    let routes = generate_route_list(slam_stack_web::app::App);

    // Initialize OIDC if configured
    let oidc_issuer = std::env::var("OIDC_ISSUER").unwrap_or_default();
    let oidc_client_id = std::env::var("OIDC_CLIENT_ID").unwrap_or_default();
    let oidc_client_secret = std::env::var("OIDC_CLIENT_SECRET").unwrap_or_default();
    let session_secret = std::env::var("SESSION_SECRET").unwrap_or_default();
    let oidc_redirect = std::env::var("OIDC_REDIRECT_URL").unwrap_or_else(|_| {
        "http://slam-stack-web.web.svc.cluster.local:8080/auth/callback".into()
    });

    let app = Router::new().leptos_routes(
        &leptos_options,
        routes,
        || view! { <slam_stack_web::app::App/> },
    );

    let app = if !oidc_issuer.is_empty() && !session_secret.is_empty() {
        match slam_stack_web::auth::OidcState::init(
            &oidc_issuer,
            &oidc_client_id,
            &oidc_client_secret,
            &oidc_redirect,
        )
        .await
        {
            Ok(oidc) => {
                eprintln!("OIDC auth enabled (issuer: {oidc_issuer})");
                let oidc = Arc::new(oidc);
                app.route("/auth/redirect", get(auth_redirect))
                    .route("/auth/callback", get(auth_callback))
                    .layer(axum::middleware::from_fn(
                        slam_stack_web::middleware::auth_middleware,
                    ))
                    .layer(axum::Extension(oidc))
                    .with_state(leptos_options)
            }
            Err(e) => {
                eprintln!("WARNING: OIDC init failed: {e} — running without auth");
                app.with_state(leptos_options)
            }
        }
    } else {
        eprintln!("WARNING: OIDC not configured — running without auth");
        app.with_state(leptos_options)
    };

    eprintln!("Slam Stack dashboard listening on http://{addr}");
    let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

#[cfg(feature = "ssr")]
async fn auth_redirect(
    axum::Extension(oidc): axum::Extension<std::sync::Arc<slam_stack_web::auth::OidcState>>,
) -> axum::response::Response {
    use axum::response::IntoResponse;
    let url = oidc.start_auth().await;
    axum::response::Redirect::to(&url).into_response()
}

#[cfg(feature = "ssr")]
async fn auth_callback(
    axum::Extension(oidc): axum::Extension<std::sync::Arc<slam_stack_web::auth::OidcState>>,
    axum::extract::Query(params): axum::extract::Query<std::collections::HashMap<String, String>>,
) -> axum::response::Response {
    use axum::response::IntoResponse;

    let code = params.get("code").map(|s| s.as_str()).unwrap_or("");
    let state = params.get("state").map(|s| s.as_str()).unwrap_or("");

    match oidc.exchange(code, state).await {
        Ok(token) => {
            let mut response = axum::response::Redirect::to("/").into_response();
            response.headers_mut().insert(
                axum::http::header::SET_COOKIE,
                format!(
                    "slam_session={token}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=28800"
                )
                .parse()
                .unwrap(),
            );
            response
        }
        Err(e) => {
            eprintln!("Auth callback error: {e}");
            axum::response::Redirect::to("/login").into_response()
        }
    }
}

#[cfg(not(feature = "ssr"))]
fn main() {
    #[cfg(target_arch = "wasm32")]
    {
        use leptos::prelude::*;
        console_error_panic_hook::set_once();
        leptos::mount_to_body(move || view! { <slam_stack_web::app::App/> });
    }
    #[cfg(not(target_arch = "wasm32"))]
    {
        panic!("Slam Stack server must be built with --features ssr");
    }
}
