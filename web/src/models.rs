use serde::{Deserialize, Serialize};

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
