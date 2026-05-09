use leptos::prelude::*;
use crate::models::*;
use crate::server;

#[component]
pub fn SecurityPage() -> impl IntoView {
    let findings = server::get_security_findings();

    let total = findings.len();
    let passed = findings.iter().filter(|f| f.status == FindingStatus::Pass).count();
    let warns = findings.iter().filter(|f| f.status == FindingStatus::Warn).count();
    let failed = findings.iter().filter(|f| f.status == FindingStatus::Fail).count();
    let score = if total > 0 { (passed as f32 / total as f32 * 100.0) as u32 } else { 0 };

    let score_color = if score >= 80 { "var(--success)" } else if score >= 50 { "var(--warning)" } else { "var(--error)" };

    view! {
        <div class="page-header">
            <h1>"Security Posture"</h1>
            <p>"Zero-trust verification and defense-in-depth status"</p>
        </div>

        <div class="metric-row">
            <div class="metric-card">
                <div class="metric-value" style=score_color>{format!("{}%", score)}</div>
                <div class="metric-label">"Security Score"</div>
            </div>
            <div class="metric-card">
                <div class="metric-value" style="color: var(--success);">{passed}</div>
                <div class="metric-label">"Passed"</div>
            </div>
            <div class="metric-card">
                <div class="metric-value" style="color: var(--warning);">{warns}</div>
                <div class="metric-label">"Warnings"</div>
            </div>
            <div class="metric-card">
                <div class="metric-value" style="color: var(--error);">{failed}</div>
                <div class="metric-label">"Failed"</div>
            </div>
        </div>

        <div>
            <div class="section-title">"Security Layers"</div>
            {findings.into_iter().map(|f| {
                let bar_css = f.status.css_class().to_string();
                let bar_width = match f.status {
                    FindingStatus::Pass => 100,
                    FindingStatus::Warn => 60,
                    FindingStatus::Fail => 25,
                };
                let status_label = f.status.label();
                view! {
                    <div class="card" style="margin-bottom: 8px;">
                        <div class="card-header">
                            <div>
                                <div class="card-title">{f.category}</div>
                                <div class="card-subtitle">{f.layer}</div>
                            </div>
                            <span class=format!("badge {}", bar_css)>{status_label}</span>
                        </div>
                        <div class="card-body">
                            <div style="font-size: 13px; color: var(--text-secondary);">{f.description}</div>
                            <div class="severity-bar">
                                <div class=format!("severity-fill {}", bar_css) style=format!("width: {}%", bar_width)></div>
                            </div>
                        </div>
                    </div>
                }
            }).collect::<Vec<_>>()}
        </div>
    }
}
