#[cfg(feature = "ssr")]
#[tokio::main]
async fn main() {
    use axum::Router;
    use leptos::prelude::*;
    use leptos_axum::{generate_route_list, LeptosRoutes};

    let conf = get_configuration(Some("Cargo.toml")).unwrap();
    let leptos_options = conf.leptos_options;
    let addr = leptos_options.site_addr;
    let routes = generate_route_list(slam_stack_web::app::App);

    let app = Router::new()
        .leptos_routes(&leptos_options, routes, || view! { <slam_stack_web::app::App/> })
        .with_state(leptos_options);

    println!("Slam Stack dashboard listening on http://{}", addr);
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
