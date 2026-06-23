# talos-vm — Local libvirt Talos cluster (IaC)

Spins up Talos Linux VMs on a local libvirt hypervisor, booted in
maintenance mode and ready for the parent `tofu/` stack to apply
machine config + bootstrap etcd + install Flux.

This is the **"automated Talos maker"** — a one-command path from zero
VMs to a cluster waiting for config. The parent stack takes over from
there.

## Why this exists

The slam-stack's `tofu/main.tf` bootstraps a Talos cluster assuming
the nodes already exist and listen on port 50000. This module creates
those nodes — Virtual Machines on libvirt, with stable IPs from
DHCP reservations, UEFI firmware, and optional Secure Boot + TPM 2.0.

## What this module does

1. Downloads a Talos qcow2 image from `factory.talos.dev` for the
   configured schematic + version + arch, caches in `.cache/`.
2. Creates a libvirt NAT network with DHCP MAC→IP reservations.
3. Creates N libvirt domains with stable MACs, UEFI firmware,
   optional Secure Boot + swtpm TPM 2.0.
4. Outputs the node IPs + bootstrap endpoint for the parent stack.

## What this module does NOT do

- **No Talos config apply.** The parent `tofu/main.tf` does that.
- **No kubeconfig fetch.** The parent stack ends with that.
- **No CNI, no Flux, no apps.** All of that is downstream.

Keeping the boundary clean means this module owns VM lifecycle, the
parent owns Talos config. State doesn't cross-contaminate.

## Prerequisites

- **libvirt + QEMU/KVM** on the hypervisor host:
  ```sh
  virsh -c qemu:///system version
  id | grep -o 'libvirt\|kvm'   # need both groups
  ```
- **OVMF + swtpm** for UEFI boot (default) and optional Secure Boot:
  ```sh
  sudo apt install ovmf swtpm swtpm-tools
  ```
- **OpenTofu >= 1.7** (or Terraform >= 1.7).
- **`curl`** for image download.

## Quick start

```sh
cd tofu/modules/talos-vm

# Configure (single-node default for slam-stack's 8 GB target)
cp examples/single-node.tfvars terraform.tfvars

# Init + apply
tofu init
tofu apply

# Verify VMs are up and in maintenance mode
virsh -c qemu:///system list
./scripts/discover-ips.sh

# Hand off to the parent stack — from repo root:
cd ../..
make cluster NODE_IP=$(tofu -chdir=tofu/modules/talos-vm output -raw bootstrap_node_ip)
```

## Boot mode

| Mode | Use case | Components |
|---|---|---|
| `uefi` (default) | Production fidelity — what every cloud provider boots today. | OVMF + per-VM NVRAM |
| `uefi-secureboot` | Maximum hardening — matches what GCP/Azure enforce. | OVMF Secure Boot variant + swtpm TPM 2.0 + SMM |
| `bios` | Legacy fallback for hosts without OVMF. | SeaBIOS |

Switch via `-var boot_mode=uefi-secureboot` or in `terraform.tfvars`.

## Variables

See [variables.tf](variables.tf). Highlights:

| Variable | Default | Description |
|----------|---------|-------------|
| `cluster_name` | `slam-stack` | Prefix for libvirt resources |
| `talos_version` | `v1.9.5` | Talos Linux release |
| `boot_mode` | `uefi` | Firmware / Secure Boot posture |
| `nodes` | single 4c/8 GB CP | List of node specs |
| `libvirt_uri` | `qemu:///system` | Local or remote hypervisor |

## Examples

- [`examples/single-node.tfvars`](examples/single-node.tfvars) — 1 CP, 8 GB
- [`examples/ha.tfvars`](examples/ha.tfvars) — 3 CP + 1 worker, 32 GB
