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
                        <Route path=StaticSegment("/security") view=pages::security::SecurityPage/>
                        <Route path=StaticSegment("/logs") view=pages::logs::LogsPage/>
                    </Routes>
                </main>
            </Router>
        </div>
    }
}

#[component]
fn Sidebar() -> impl IntoView {
    let location = leptos_router::hooks::use_location();

    let is_active = move |path: &str| {
        location.pathname.get().starts_with(path)
    };

    view! {
        <aside class="sidebar">
            <div class="sidebar-brand">
                <span>"⚡"</span>
                <span>"SLAM STACK"</span>
            </div>
            <nav class="sidebar-nav">
                <a
                    href="/"
                    class:active=move || is_active("/") && location.pathname.get() == "/"
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
            <div style="border-top: 1px solid var(--border); padding-top: 12px; font-size: 11px; color: var(--text-muted);">
                "v0.1.0 · Rust 100%"
            </div>
        </aside>
    }
}
