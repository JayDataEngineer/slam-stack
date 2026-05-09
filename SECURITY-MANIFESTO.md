# Security Manifesto — SLAM Stack

## Why This Exists

This stack was built because data was stolen. Once. Never again.

Every design decision optimizes for one thing: **make it impossible for anyone — including a nation-state adversary — to read, modify, or exfiltrate data without physical possession of the hardware AND the hardware tokens.**

Low resource usage is a close second. This runs on a single machine you can carry.

---

## Threat Model

**Assume the attacker:**
- Has zero-day exploits for Linux kernels, container runtimes, and network stacks
- Can intercept all network traffic (man-in-the-middle)
- Has compromised upstream container registries or Helm chart repositories
- Has physical proximity (but not physical access to powered-on hardware)
- Can attempt supply chain attacks via dependency poisoning
- Has unlimited computing resources for cryptanalysis
- Can attempt social engineering against the operator
- Controls DNS infrastructure and can issue fraudulent certificates

**What we do NOT protect against:**
- Physical access to powered-on, unlocked hardware (game over for any system)
- Rubber-hose cryptanalysis (compulsion of the operator)
- Side-channel attacks requiring physical proximity (< 1 meter)
- Kernel-level zero-days in the specific running kernel version (mitigated by immutable OS + Tetragon, not eliminated)

---

## Design Principles

### 1. Defense in Depth — Every Layer Fights Back

```
Hardware TPM → Immutable OS → eBPF Runtime → Network Zero-Trust → Admission Control → Encrypted Storage → Tamper-Evident Audit
```

No single compromise grants access. An attacker who breaks out of a container hits Tetragon. An attacker who bypasses Tetragon hits Cilium default-deny. An attacker who bypasses the network hits read-only rootfs. Every layer is independently effective.

### 2. Default Deny — Nothing is Allowed Unless Explicitly Permitted

- No pod talks to any other pod without a CiliumNetworkPolicy
- No pod reaches the internet without explicit egress rules
- No unsigned container image runs — ever
- No shell execution inside pods — Tetragon kills the process at the kernel level
- No inbound ports open — access only via Headscale mesh tunnel

### 3. Immutable Infrastructure — Nothing Can Be Modified at Runtime

- TalOS: no SSH, no shell, no package manager — API-only management with mTLS
- Containers: read-only root filesystem, no privilege escalation, all capabilities dropped
- Storage: WORM mode for audit logs and backups
- Network: policies are enforced at the kernel level (eBPF/Cilium), not in userspace

### 4. Ephemeral Credentials — Nothing Lasts Long Enough to Steal

- Database credentials rotate every 15 minutes (Vault dynamic secrets)
- TLS certificates auto-rotate every 24 hours (Vault PKI)
- Secret storage is tmpfs only — secrets never touch persistent disk
- Vault itself auto-unseals from TPM — no manual unseal keys to lose

### 5. Cryptographic Verification — Trust Math, Not People

- Every container image is Cosign-signed — Kyverno enforces at admission time
- Audit logs are forward-chained HMAC signed — tampering breaks the chain
- Backups are encrypted + Cosign-signed — tampering is detectable
- All pod-to-pod traffic is WireGuard encrypted at the kernel level
- Storage encryption keys are managed by Vault Transit — never on disk

### 6. Hardware Root of Trust — The Physical Machine is the Anchor

- TPM 2.0 binds disk encryption to specific hardware
- Secure Boot ensures only signed kernels boot
- Measured boot creates tamper-evident boot log
- YubiKey (when acquired) holds signing keys — cannot be extracted remotely

---

## What Happens If You're Compromised

| Attack Vector | What Stops It | Fallback |
|---|---|---|
| Container escape | Tetragon kills shell/process injection | Read-only rootfs limits damage |
| Unsigned image deploy | Kyverno blocks at admission | Cosign verification on deploy |
| Network lateral movement | Cilium default-deny | WireGuard encryption prevents sniffing |
| Stolen credentials | 15-minute rotation | Vault audit log shows who accessed what |
| Physical disk theft | TPM-bound LUKS encryption | Keys never exist off-chip |
| DNS exfiltration | DNS query restrictions, no ANY queries | Hubble alerts on anomalies |
| Supply chain attack | Cosign image signing, Kyverno enforcement | Helm chart verification on deploy |
| Memory dump | Tetragon blocks /dev/mem, gdb, ptrace | mlock prevents swap leakage |
| Privilege escalation | No SUID binaries (Tetragon kills sudo/su) | No privilege escalation in pod spec |
| Brute force auth | 3 attempts then 1-hour lockout | Rate limiting on all auth endpoints |

---

## Operational Security

**The human is always the weakest link.** No amount of software hardening helps if:
- You expose the Talos API endpoint publicly
- You store the kubeconfig on an unencrypted laptop
- You skip image signing and deploy unsigned images "just this once"
- You disable Tetragon policies because something broke
- You reuse passwords across services

This stack is a tool. It enforces security automatically so you don't have to remember. But it cannot protect against the operator working around it.

---

## Verification

Run `./verify.sh` after any change. It checks:
- All kernel parameters are applied
- All network policies are active
- Tetragon kills shell execution
- Kyverno blocks unsigned images
- Vault is sealed/unsealed correctly
- All images are signed
- Audit logs are flowing
- TPM measurements are valid

If any check fails, the cluster is not secure. Do not deploy to production.
