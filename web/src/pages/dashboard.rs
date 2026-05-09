use leptos::prelude::*;
use crate::models::*;
use crate::server;

#[component]
pub fn DashboardPage() -> impl IntoView {
    let metrics = server::get_metrics();
    let components = server::get_components();

    let healthy = components.iter().filter(|c| c.status == Status::Healthy).count();
    let warnings = components.iter().filter(|c| c.status == Status::Warning).count();
    let errors = components.iter().filter(|c| c.status == Status::Error).count();
    let total_ram: u32 = components.iter().map(|c| c.ram_mb).sum();

    view! {
        <div class="page-header">
            <h1>"Dashboard"</h1>
            <p>"Cluster status and component health overview"</p>
        </div>

        <div class="metric-row">
            <div class="metric-card">
                <div class="metric-value" style="color: var(--accent-cyan);">{metrics.pod_count}</div>
                <div class="metric-label">"Active Pods"</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">{format!("{:.0}%", metrics.cpu_usage_pct)}</div>
                <div class="metric-label">"CPU Usage"</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">
                    {format!("{} / {} MB", metrics.ram_used_mb, metrics.ram_total_mb)}
                </div>
                <div class="metric-label">"RAM Usage"</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">{format!("{}h", metrics.uptime_hours)}</div>
                <div class="metric-label">"Uptime"</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">
                    {format!("{} / {} GB", metrics.disk_used_mb / 1024, metrics.disk_total_mb / 1024)}
                </div>
                <div class="metric-label">"Disk Usage"</div>
            </div>
        </div>

        <div class="summary-row">
            <div class="summary-item">
                <span class="summary-count" style="color: var(--success);">{healthy}</span>
                <span class="summary-label">"Healthy"</span>
            </div>
            <div class="summary-item">
                <span class="summary-count" style="color: var(--warning);">{warnings}</span>
                <span class="summary-label">"Warnings"</span>
            </div>
            <div class="summary-item">
                <span class="summary-count" style="color: var(--error);">{errors}</span>
                <span class="summary-label">"Errors"</span>
            </div>
            <div class="summary-item">
                <span class="summary-count">{format!("~{} MiB", total_ram)}</span>
                <span class="summary-label">"Total RAM Budget"</span>
            </div>
        </div>

        <div>
            <div class="section-title">"Stack Components"</div>
            <div class="status-grid">
                {components.into_iter().map(|c| {
                    let status_class = c.status.css_class().to_string();
                    let lang_class = c.language.to_lowercase();
                    view! {
                        <div class="card">
                            <div class="card-header">
                                <div class="card-title">{c.name}</div>
                                <span class=format!("status-dot {}", status_class)></span>
                            </div>
                            <div class="card-body">
                                <div class="card-subtitle">{c.description}</div>
                                <div class="card-stat">
                                    <span class="card-stat-label">"Status"</span>
                                    <span class="card-stat-value">{c.status.label()}</span>
                                </div>
                                <div class="card-stat">
                                    <span class="card-stat-label">"Language"</span>
                                    <span class=format!("badge {}", lang_class)>{c.language}</span>
                                </div>
                                <div class="card-stat">
                                    <span class="card-stat-label">"Version"</span>
                                    <span class="card-stat-value">{c.version}</span>
                                </div>
                                <div class="card-stat">
                                    <span class="card-stat-label">"RAM"</span>
                                    <span class="card-stat-value">{format!("{} MB", c.ram_mb)}</span>
                                </div>
                                <div class="card-stat">
                                    <span class="card-stat-label">"Namespace"</span>
                                    <span class="card-stat-value" style="color: var(--text-muted);">{c.namespace}</span>
                                </div>
                            </div>
                        </div>
                    }
                }).collect::<Vec<_>>()}
            </div>
        </div>
    }
}
