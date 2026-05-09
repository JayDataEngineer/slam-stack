use crate::models::*;

pub fn get_components() -> Vec<ComponentStatus> {
    vec![
        ComponentStatus {
            name: "Talos Linux",
            status: Status::Healthy,
            language: "Go",
            version: "1.13.0",
            ram_mb: 800,
            namespace: "system",
            description: "Immutable K8s OS, no shell",
        },
        ComponentStatus {
            name: "Cilium",
            status: Status::Healthy,
            language: "Go/Rust",
            version: "1.20.0",
            ram_mb: 300,
            namespace: "kube-system",
            description: "eBPF networking + WireGuard",
        },
        ComponentStatus {
            name: "Tetragon",
            status: Status::Healthy,
            language: "Go/C",
            version: "1.4.0",
            ram_mb: 200,
            namespace: "kube-system",
            description: "eBPF runtime enforcement",
        },
        ComponentStatus {
            name: "Kyverno",
            status: Status::Healthy,
            language: "Go",
            version: "1.14.0",
            ram_mb: 150,
            namespace: "kyverno",
            description: "Admission policy engine",
        },
        ComponentStatus {
            name: "Kanidm",
            status: Status::Healthy,
            language: "Rust",
            version: "1.6.0",
            ram_mb: 80,
            namespace: "identity",
            description: "Passkey-only identity provider",
        },
        ComponentStatus {
            name: "OpenBao",
            status: Status::Healthy,
            language: "Go",
            version: "2.5.3",
            ram_mb: 300,
            namespace: "vault",
            description: "Ephemeral secrets engine",
        },
        ComponentStatus {
            name: "SurrealDB",
            status: Status::Healthy,
            language: "Rust",
            version: "2.3.7",
            ram_mb: 300,
            namespace: "database",
            description: "Multi-model database",
        },
        ComponentStatus {
            name: "Stalwart",
            status: Status::Warning,
            language: "Rust",
            version: "0.12.0",
            ram_mb: 150,
            namespace: "mail",
            description: "Rust mail server (SMTP+JMAP)",
        },
        ComponentStatus {
            name: "RustFS",
            status: Status::Healthy,
            language: "Rust",
            version: "0.8.0",
            ram_mb: 300,
            namespace: "storage",
            description: "S3 with WORM compliance",
        },
        ComponentStatus {
            name: "VictoriaLogs",
            status: Status::Healthy,
            language: "Go",
            version: "1.50.0",
            ram_mb: 200,
            namespace: "observability",
            description: "Immutable audit storage",
        },
        ComponentStatus {
            name: "Headscale",
            status: Status::Healthy,
            language: "Go",
            version: "0.25.0",
            ram_mb: 50,
            namespace: "network",
            description: "WireGuard mesh VPN",
        },
    ]
}

pub fn get_metrics() -> ClusterMetrics {
    ClusterMetrics {
        cpu_usage_pct: 23.4,
        ram_used_mb: 2830,
        ram_total_mb: 8192,
        disk_used_mb: 14200,
        disk_total_mb: 102400,
        pod_count: 34,
        uptime_hours: 168,
    }
}

pub fn get_logs() -> Vec<LogEntry> {
    vec![
        LogEntry {
            timestamp: "2026-05-08T14:32:01Z".into(),
            level: LogLevel::Info,
            source: "cilium".into(),
            message: "WireGuard encryption active for all pod-to-pod traffic".into(),
        },
        LogEntry {
            timestamp: "2026-05-08T14:31:45Z".into(),
            level: LogLevel::Info,
            source: "kyverno".into(),
            message: "Admission policy 'require-image-signature' enforced: 12 pods verified".into(),
        },
        LogEntry {
            timestamp: "2026-05-08T14:30:22Z".into(),
            level: LogLevel::Warn,
            source: "tetragon".into(),
            message: "Blocked shell execution attempt in namespace 'staging' (pod: debug-pod)".into(),
        },
        LogEntry {
            timestamp: "2026-05-08T14:28:00Z".into(),
            level: LogLevel::Info,
            source: "vault".into(),
            message: "Rotated SurrealDB credentials for role 'slam-stack-app' (expired 15m)".into(),
        },
        LogEntry {
            timestamp: "2026-05-08T14:25:13Z".into(),
            level: LogLevel::Info,
            source: "kanidm".into(),
            message: "OIDC token issued for user 'admin' (WebAuthn assertion)".into(),
        },
        LogEntry {
            timestamp: "2026-05-08T14:20:00Z".into(),
            level: LogLevel::Info,
            source: "talos".into(),
            message: "etcd snapshot completed: 4.2MB, uploaded to RustFS".into(),
        },
        LogEntry {
            timestamp: "2026-05-08T14:15:30Z".into(),
            level: LogLevel::Debug,
            source: "cilium".into(),
            message: "Network policy 'allow-to-kanidm' matched 3 endpoints".into(),
        },
        LogEntry {
            timestamp: "2026-05-08T14:00:00Z".into(),
            level: LogLevel::Info,
            source: "headscale".into(),
            message: "Node 'admin-laptop' joined mesh (public key: nodekey:a1b2c3...)".into(),
        },
        LogEntry {
            timestamp: "2026-05-08T13:45:22Z".into(),
            level: LogLevel::Error,
            source: "stalwart".into(),
            message: "SMTP connection rejected: TLS handshake failed (untrusted cert)".into(),
        },
        LogEntry {
            timestamp: "2026-05-08T13:30:00Z".into(),
            level: LogLevel::Info,
            source: "surreal-db".into(),
            message: "WAL checkpoint completed: 128MB reclaimed".into(),
        },
        LogEntry {
            timestamp: "2026-05-08T13:15:00Z".into(),
            level: LogLevel::Warn,
            source: "tetragon".into(),
            message: "Blocked crypto miner binary execution in namespace 'monitoring' (pod: grafana-agent)".into(),
        },
        LogEntry {
            timestamp: "2026-05-08T12:00:00Z".into(),
            level: LogLevel::Info,
            source: "kyverno".into(),
            message: "CIS Benchmark scan completed: 47/50 checks passed".into(),
        },
    ]
}

pub fn get_security_findings() -> Vec<SecurityFinding> {
    vec![
        SecurityFinding {
            category: "OS Immutability",
            status: FindingStatus::Pass,
            description: "Talos Linux: no shell, no SSH, read-only rootfs",
            layer: "Hardware/OS",
        },
        SecurityFinding {
            category: "TPM Disk Encryption",
            status: FindingStatus::Warn,
            description: "Disk encryption configured but TPM attestation not verified",
            layer: "Hardware/OS",
        },
        SecurityFinding {
            category: "Network Zero-Trust",
            status: FindingStatus::Pass,
            description: "Cilium default-deny + WireGuard encryption active",
            layer: "Network",
        },
        SecurityFinding {
            category: "MicroVM Isolation",
            status: FindingStatus::Fail,
            description: "Kata Containers extension not loaded (dev cluster)",
            layer: "Compute",
        },
        SecurityFinding {
            category: "Supply Chain",
            status: FindingStatus::Pass,
            description: "Cosign signature enforcement via Kyverno",
            layer: "Build/Deploy",
        },
        SecurityFinding {
            category: "Runtime Enforcement",
            status: FindingStatus::Pass,
            description: "Tetragon killing shell/mount/crypto-miner syscalls",
            layer: "Runtime",
        },
        SecurityFinding {
            category: "Identity",
            status: FindingStatus::Pass,
            description: "Kanidm with mandatory WebAuthn (no passwords)",
            layer: "Identity",
        },
        SecurityFinding {
            category: "Credential Rotation",
            status: FindingStatus::Pass,
            description: "Vault dynamic secrets: 15m DB credential rotation",
            layer: "Secrets",
        },
        SecurityFinding {
            category: "Audit Trail",
            status: FindingStatus::Warn,
            description: "VictoriaLogs receiving streams, WORM lock not verified",
            layer: "Observability",
        },
        SecurityFinding {
            category: "Pod Security",
            status: FindingStatus::Pass,
            description: "All pods: non-root, read-only rootfs, no priv esc",
            layer: "Workload",
        },
    ]
}
