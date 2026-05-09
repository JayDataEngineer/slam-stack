use serde::{Deserialize, Serialize};

// === Component Status (dashboard) ===

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComponentStatus {
    pub name: &'static str,
    pub status: Status,
    pub language: &'static str,
    pub version: &'static str,
    pub ram_mb: u32,
    pub namespace: &'static str,
    pub description: &'static str,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum Status {
    Healthy,
    Warning,
    Error,
    Unknown,
}

impl Status {
    pub fn css_class(&self) -> &'static str {
        match self {
            Status::Healthy => "healthy",
            Status::Warning => "warning",
            Status::Error => "error",
            Status::Unknown => "unknown",
        }
    }

    pub fn label(&self) -> &'static str {
        match self {
            Status::Healthy => "Healthy",
            Status::Warning => "Warning",
            Status::Error => "Error",
            Status::Unknown => "Unknown",
        }
    }
}

// === Cluster Metrics ===

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClusterMetrics {
    pub cpu_usage_pct: f32,
    pub ram_used_mb: u32,
    pub ram_total_mb: u32,
    pub disk_used_mb: u32,
    pub disk_total_mb: u32,
    pub pod_count: u32,
    pub uptime_hours: u32,
}

// === Log Entries ===

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogEntry {
    pub timestamp: String,
    pub level: LogLevel,
    pub source: String,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum LogLevel {
    Debug,
    Info,
    Warn,
    Error,
}

impl LogLevel {
    pub fn css_class(&self) -> &'static str {
        match self {
            LogLevel::Debug => "debug",
            LogLevel::Info => "info",
            LogLevel::Warn => "warn",
            LogLevel::Error => "error",
        }
    }

    pub fn label(&self) -> &'static str {
        match self {
            LogLevel::Debug => "DEBUG",
            LogLevel::Info => "INFO",
            LogLevel::Warn => "WARN",
            LogLevel::Error => "ERROR",
        }
    }
}

// === Security Findings ===

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecurityFinding {
    pub category: &'static str,
    pub status: FindingStatus,
    pub description: &'static str,
    pub layer: &'static str,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum FindingStatus {
    Pass,
    Fail,
    Warn,
}

impl FindingStatus {
    pub fn css_class(&self) -> &'static str {
        match self {
            FindingStatus::Pass => "safe",
            FindingStatus::Fail => "high",
            FindingStatus::Warn => "medium",
        }
    }

    pub fn label(&self) -> &'static str {
        match self {
            FindingStatus::Pass => "PASS",
            FindingStatus::Fail => "FAIL",
            FindingStatus::Warn => "WARN",
        }
    }
}

// === Incidents (SurrealDB-backed CRUD) ===

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum IncidentSeverity {
    Critical,
    High,
    Medium,
    Low,
}

impl IncidentSeverity {
    pub fn label(&self) -> &'static str {
        match self {
            IncidentSeverity::Critical => "Critical",
            IncidentSeverity::High => "High",
            IncidentSeverity::Medium => "Medium",
            IncidentSeverity::Low => "Low",
        }
    }

    pub fn css_class(&self) -> &'static str {
        match self {
            IncidentSeverity::Critical => "severity-critical",
            IncidentSeverity::High => "severity-high",
            IncidentSeverity::Medium => "severity-medium",
            IncidentSeverity::Low => "severity-low",
        }
    }

    pub fn all() -> Vec<Self> {
        vec![
            IncidentSeverity::Critical,
            IncidentSeverity::High,
            IncidentSeverity::Medium,
            IncidentSeverity::Low,
        ]
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum IncidentStatus {
    Open,
    Investigating,
    Contained,
    Resolved,
}

impl IncidentStatus {
    pub fn label(&self) -> &'static str {
        match self {
            IncidentStatus::Open => "Open",
            IncidentStatus::Investigating => "Investigating",
            IncidentStatus::Contained => "Contained",
            IncidentStatus::Resolved => "Resolved",
        }
    }

    pub fn css_class(&self) -> &'static str {
        match self {
            IncidentStatus::Open => "status-open",
            IncidentStatus::Investigating => "status-investigating",
            IncidentStatus::Contained => "status-contained",
            IncidentStatus::Resolved => "status-resolved",
        }
    }

    pub fn all() -> Vec<Self> {
        vec![
            IncidentStatus::Open,
            IncidentStatus::Investigating,
            IncidentStatus::Contained,
            IncidentStatus::Resolved,
        ]
    }
}

/// Incident as stored in SurrealDB (read model)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Incident {
    pub id: String,
    pub title: String,
    pub description: String,
    pub severity: IncidentSeverity,
    pub status: IncidentStatus,
    pub created_at: String,
    pub updated_at: String,
}

/// New incident form data (write model — no ID or timestamps)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NewIncident {
    pub title: String,
    pub description: String,
    pub severity: IncidentSeverity,
}

// === Authentication (OIDC) ===

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserIdentity {
    pub subject: String,
    pub email: String,
    pub name: String,
}
