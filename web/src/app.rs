use leptos::prelude::*;
use leptos_router::components::{Route, Router, Routes};
use leptos_router::StaticSegment;

use crate::pages;

#[component]
pub fn App() -> impl IntoView {
    leptos_meta::provide_meta_context();

    view! {
        <div class="app-layout">
            <Router>
                <Sidebar/>
                <main class="main-content">
                    <Routes fallback=|| view! { <div class="loading"><h1>"Not Found"</h1></div> }>
                        <Route path=StaticSegment("/") view=pages::dashboard::DashboardPage/>
                        <Route path=StaticSegment("/login") view=pages::login::LoginPage/>
                        <Route path=StaticSegment("/security") view=pages::security::SecurityPage/>
                        <Route path=StaticSegment("/logs") view=pages::logs::LogsPage/>
                        <Route path=StaticSegment("/incidents") view=pages::incidents::IncidentsPage/>
                    </Routes>
                </main>
            </Router>
        </div>
    }
}

#[component]
fn Sidebar() -> impl IntoView {
    let location = leptos_router::hooks::use_location();
    let user_action = Action::new(|_: &()| crate::server::get_current_user());
    user_action.dispatch(());
    let user_result = user_action.value();

    let is_active = move |path: &str| {
        let current = location.pathname.get();
        if path == "/" {
            current == "/"
        } else {
            current.starts_with(path)
        }
    };

    view! {
        <aside class="sidebar">
            <div class="sidebar-brand">
                <span>"SLAM"</span>
            </div>
            <nav class="sidebar-nav">
                <a
                    href="/"
                    class:active=move || is_active("/")
                    class="nav-item"
                >
                    <svg class="nav-icon" viewBox="0 0 16 16" fill="currentColor">
                        <path d="M8 1l-7 7h2v6h4v-4h2v4h4V8h2L8 1z"/>
                    </svg>
                    "Dashboard"
                </a>
                <a
                    href="/security"
                    class:active=move || is_active("/security")
                    class="nav-item"
                >
                    <svg class="nav-icon" viewBox="0 0 16 16" fill="currentColor">
                        <path d="M8 1L2 3v5c0 3.5 2.5 6.5 6 7 3.5-.5 6-3.5 6-7V3L8 1z"/>
                    </svg>
                    "Security"
                </a>
                <a
                    href="/incidents"
                    class:active=move || is_active("/incidents")
                    class="nav-item"
                >
                    <svg class="nav-icon" viewBox="0 0 16 16" fill="currentColor">
                        <path d="M8.5 1a.5.5 0 0 0-1 0v6a.5.5 0 0 0 1 0V1zM6.5 3a.5.5 0 0 0-1 0v4a.5.5 0 0 0 1 0V3zm4 0a.5.5 0 0 0-1 0v4a.5.5 0 0 0 1 0V3zM4.5 5a.5.5 0 0 0-1 0v3a.5.5 0 0 0 1 0V5zm7 0a.5.5 0 0 0-1 0v3a.5.5 0 0 0 1 0V5zM3 8.5A3.5 3.5 0 0 0 6.5 12h3a3.5 3.5 0 0 0 1.5-6.66V4.5a4.5 4.5 0 0 0-9 0v.84A3.5 3.5 0 0 0 3 8.5z"/>
                    </svg>
                    "Incidents"
                </a>
                <a
                    href="/logs"
                    class:active=move || is_active("/logs")
                    class="nav-item"
                >
                    <svg class="nav-icon" viewBox="0 0 16 16" fill="currentColor">
                        <path d="M2 2h12v2H2V2zm0 4h12v2H2V6zm0 4h8v2H2v-2z"/>
                    </svg>
                    "Logs"
                </a>
            </nav>
            <div class="sidebar-footer">
                {move || match user_result.get() {
                    Some(Ok(Some(user))) => view! {
                        <>
                            <span class="user-name">{user.name}</span>
                            " · v0.2.0"
                        </>
                    }.into_any(),
                    _ => view! { <span>"v0.2.0 · Rust/WASM"</span> }.into_any(),
                }}
            </div>
        </aside>
    }
}
