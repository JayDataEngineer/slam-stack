use leptos::prelude::*;

#[component]
pub fn LoginPage() -> impl IntoView {
    view! {
        <div class="login-page">
            <div class="login-card">
                <h1>"SLAM Stack"</h1>
                <p>"Sign in to access the security dashboard"</p>
                <a href="/auth/redirect" class="login-button">
                    "Sign in with Kanidm"
                </a>
            </div>
        </div>
    }
}
