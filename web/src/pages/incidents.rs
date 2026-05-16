use leptos::prelude::*;
use leptos::ev::SubmitEvent;
use leptos::server_fn::ServerFnError;

use crate::models::*;
use crate::server;

#[component]
pub fn IncidentsPage() -> impl IntoView {
    let incidents = Resource::new(
        || (),
        |_| async { server::get_incidents().await },
    );

    let show_form = RwSignal::new(false);

    let create_action = Action::new(move |(title, desc, sev): &(String, String, String)| {
        let (title, desc, sev) = (title.clone(), desc.clone(), sev.clone());
        async move {
            let result = server::create_incident(title, desc, sev).await;
            incidents.refetch();
            result
        }
    });

    let delete_action = Action::new(move |id: &String| {
        let id = id.clone();
        async move {
            let result = server::delete_incident(id).await;
            incidents.refetch();
            result
        }
    });

    let status_action = Action::new(move |(id, status): &(String, String)| {
        let (id, status) = (id.clone(), status.clone());
        async move {
            let result = server::update_incident_status(id, status).await;
            incidents.refetch();
            result
        }
    });

    view! {
        <div class="page-header">
            <h1>"Incidents"</h1>
            <p>"Security incident tracking — backed by PostgreSQL"</p>
        </div>

        <div class="toolbar">
            <button
                class="btn btn-primary"
                on:click=move |_| show_form.update(|v| *v = !*v)
            >
                {move || if show_form.get() { "Cancel" } else { "+ New Incident" }}
            </button>
        </div>

        <Show
            when=move || show_form.get()
        >
            <IncidentForm action=create_action on_done=move || show_form.set(false)/>
        </Show>

        {move || match create_action.value().get() {
            Some(Err(e)) => Some(view! {
                <div class="alert alert-error">{format!("Create failed: {e}")}</div>
            }),
            _ => None,
        }}

        {move || match delete_action.value().get() {
            Some(Err(e)) => Some(view! {
                <div class="alert alert-error">{format!("Delete failed: {e}")}</div>
            }),
            _ => None,
        }}

        <Suspense fallback=|| view! { <div class="loading">"Loading incidents..."</div> }>
            {move || {
                incidents.get().map(|result| {
                    match result {
                        Ok(data) => view! {
                            <IncidentTable
                                incidents=data
                                on_delete=move |id: String| { delete_action.dispatch(id); }
                                on_status=move |(id, s): (String, String)| { status_action.dispatch((id, s)); }
                            />
                        }.into_any(),
                        Err(e) => view! {
                            <div class="alert alert-error">{format!("Failed to load: {e}")}</div>
                        }.into_any(),
                    }
                })
            }}
        </Suspense>
    }
}

#[component]
fn IncidentForm<F: Fn() + 'static>(
    action: Action<(String, String, String), Result<(), ServerFnError>>,
    on_done: F,
) -> impl IntoView {
    let title = RwSignal::new(String::new());
    let description = RwSignal::new(String::new());
    let severity = RwSignal::new("Medium".to_string());

    let on_submit = move |ev: SubmitEvent| {
        ev.prevent_default();
        let t = title.get();
        let d = description.get();
        let s = severity.get();
        if t.is_empty() { return; }
        action.dispatch((t, d, s));
        title.set(String::new());
        description.set(String::new());
        on_done();
    };

    view! {
        <div class="card form-card">
            <form on:submit=on_submit>
                <div class="form-group">
                    <label class="form-label">"Title"</label>
                    <input
                        class="form-input"
                        type="text"
                        placeholder="Brief description of the incident"
                        prop:value=move || title.get()
                        on:input=move |ev| title.set(event_target_value(&ev))
                        required
                    />
                </div>

                <div class="form-group">
                    <label class="form-label">"Description"</label>
                    <textarea
                        class="form-input form-textarea"
                        placeholder="Detailed description, affected systems, initial assessment"
                        prop:value=move || description.get()
                        on:input=move |ev| description.set(event_target_value(&ev))
                    ></textarea>
                </div>

                <div class="form-group">
                    <label class="form-label">"Severity"</label>
                    <div class="severity-select">
                        {vec!["Critical", "High", "Medium", "Low"].into_iter().map(|sev| {
                            let sev_owned = sev.to_string();
                            let css = match sev {
                                "Critical" => "severity-critical",
                                "High" => "severity-high",
                                "Medium" => "severity-medium",
                                _ => "severity-low",
                            }.to_string();
                            let css_for_click = css.clone();
                            let sev_for_click = sev_owned.clone();
                            view! {
                                <button
                                    type="button"
                                    class=format!("btn btn-sm severity-btn {}", css)
                                    class:severity-selected=move || severity.get() == sev_owned
                                    on:click=move |_| severity.set(sev_for_click.clone())
                                >
                                    {sev_owned.clone()}
                                </button>
                            }
                        }).collect::<Vec<_>>()}
                    </div>
                </div>

                <div class="form-actions">
                    <button type="submit" class="btn btn-primary">"Create Incident"</button>
                </div>
            </form>
        </div>
    }
}

#[component]
fn IncidentTable<F: Fn(String) + Clone + 'static, G: Fn((String, String)) + Clone + 'static>(
    incidents: Vec<Incident>,
    on_delete: F,
    on_status: G,
) -> impl IntoView {
    if incidents.is_empty() {
        return view! {
            <div class="card empty-state">
                <div class="empty-icon">"!"</div>
                <h3>"No incidents recorded"</h3>
                <p>"Click '+ New Incident' to create your first security incident."</p>
            </div>
        }.into_any();
    }

    let statuses = vec!["Open", "Investigating", "Contained", "Resolved"];

    // Clone callbacks for use in FnMut closure
    let on_status_clone = on_status.clone();
    let on_delete_clone = on_delete.clone();

    view! {
        <div class="table-wrapper">
            <table class="data-table">
                <thead>
                    <tr>
                        <th>"Severity"</th>
                        <th>"Title"</th>
                        <th>"Status"</th>
                        <th>"Created"</th>
                        <th>"Actions"</th>
                    </tr>
                </thead>
                <tbody>
                    {incidents.into_iter().map(|inc| {
                        let inc_id = inc.id.clone();
                        let inc_id2 = inc.id.clone();
                        let current_status = inc.status.label().to_string();
                        let on_s = on_status_clone.clone();
                        let on_d = on_delete_clone.clone();
                        let statuses = statuses.clone();

                        let sev_css = inc.severity.css_class().to_string();
                        let sev_label = inc.severity.label().to_string();

                        view! {
                            <tr>
                                <td>
                                    <span class=format!("severity-badge {}", sev_css)>
                                        {sev_label}
                                    </span>
                                </td>
                                <td>
                                    <div class="incident-title">{inc.title}</div>
                                    <div class="incident-desc">{inc.description}</div>
                                </td>
                                <td>
                                    <select
                                        class="status-select"
                                        on:change=move |ev| {
                                            let new_status = event_target_value(&ev);
                                            on_s((inc_id2.clone(), new_status));
                                        }
                                    >
                                        {statuses.iter().map(|s| {
                                            let selected = *s == current_status;
                                            view! {
                                                <option value=*s selected=selected>{*s}</option>
                                            }
                                        }).collect::<Vec<_>>()}
                                    </select>
                                </td>
                                <td class="cell-muted">
                                    {format_ts(&inc.created_at)}
                                </td>
                                <td>
                                    <button
                                        class="btn btn-danger btn-sm"
                                        on:click=move |_| on_d(inc_id.clone())
                                    >
                                        "Delete"
                                    </button>
                                </td>
                            </tr>
                        }
                    }).collect::<Vec<_>>()}
                </tbody>
            </table>
        </div>
    }.into_any()
}

fn format_ts(ts: &str) -> String {
    if let Ok(parsed) = chrono::DateTime::parse_from_rfc3339(ts) {
        let now = chrono::Utc::now();
        let diff = now.signed_duration_since(parsed);
        if diff.num_minutes() < 1 { return "just now".into(); }
        if diff.num_hours() < 1 { return format!("{}m ago", diff.num_minutes()); }
        if diff.num_hours() < 24 { return format!("{}h ago", diff.num_hours()); }
        return format!("{}", parsed.format("%Y-%m-%d %H:%M"));
    }
    ts.to_string()
}
