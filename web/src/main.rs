#[cfg(feature = "ssr")]
#[tokio::main]
async fn main() {
    use axum::Router;
    use leptos::prelude::*;
    use leptos_axum::{generate_route_list, LeptosRoutes};

    // Initialize SurrealDB connection
    let db_url =
        std::env::var("SURREALDB_URL").unwrap_or_else(|_| "http://surrealdb.database.svc.cluster.local:8000".into());
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

    let app = Router::new()
        .leptos_routes(&leptos_options, routes, || view! { <slam_stack_web::app::App/> })
        .with_state(leptos_options);

    eprintln!("Slam Stack dashboard listening on http://{addr}");
    let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
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
