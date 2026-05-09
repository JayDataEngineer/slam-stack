use leptos::prelude::*;
use crate::server;

#[component]
pub fn LogsPage() -> impl IntoView {
    let logs = server::get_logs();

    view! {
        <div class="page-header">
            <h1>"Audit Logs"</h1>
            <p>"Immutable event stream from all cluster components"</p>
        </div>

        <div class="log-viewer">
            <div class="log-entry" style="color: var(--text-muted); font-weight: 600; border-bottom: 1px solid var(--border); padding-bottom: 8px; margin-bottom: 4px;">
                <span>"Timestamp"</span>
                <span>"Level"</span>
                <span>"Source"</span>
                <span>"Message"</span>
            </div>
            {logs.into_iter().map(|entry| {
                let level_css = entry.level.css_class().to_string();
                let level_label = entry.level.label();
                view! {
                    <div class="log-entry">
                        <span class="log-time">{entry.timestamp}</span>
                        <span class=format!("log-level {}", level_css)>{level_label}</span>
                        <span class="log-source">{entry.source}</span>
                        <span class="log-message">{entry.message}</span>
                    </div>
                }
            }).collect::<Vec<_>>()}
        </div>
    }
}
