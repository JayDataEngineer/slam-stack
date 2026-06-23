###############################################################################
# Cluster shape
###############################################################################

variable "cluster_name" {
  type        = string
  description = "Cluster name used as a prefix for libvirt resources (network, domains, volumes). Keep short — libvirt caps domain names at 63 chars."
  default     = "slam-stack"
}

###############################################################################
# Talos image
###############################################################################
#
# Two values together identify an immutable image from factory.talos.dev:
#   schematic_id  — SHA256 of the extension set. For pure x86_64 VMs without
#                   extensions, the bare-metal schematic works:
#                   376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d683354a
#   talos_version — Talos Linux release, e.g. v1.9.5. Must match what the
#                   schematic was built against.

variable "talos_schematic_id" {
  type        = string
  description = "64-char hex schematic ID from https://factory.talos.dev."
  default     = "376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d683354a"
}

variable "talos_version" {
  type        = string
  description = "Talos Linux version (e.g. v1.9.5). Must exist as a release on factory.talos.dev for the chosen schematic."
  default     = "v1.9.5"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version baked into the Talos image (e.g. v1.32.0). Must be compatible with talos_version."
  default     = "v1.32.0"
}

variable "cpu_arch" {
  type        = string
  description = "CPU architecture the VMs are built for. Must match the schematic."
  default     = "amd64"

  validation {
    condition     = contains(["amd64", "arm64"], var.cpu_arch)
    error_message = "cpu_arch must be amd64 or arm64."
  }
}

###############################################################################
# Network
###############################################################################

variable "network_cidr" {
  type        = string
  description = "CIDR for the libvirt NAT network. Default avoids libvirt's default 192.168.122.0/24 and common homelab ranges."
  default     = "192.168.130.0/24"
}

variable "network_name" {
  type        = string
  description = "libvirt network name. Prefixed with cluster_name to namespace."
  default     = "talos-net"
}

###############################################################################
# Node topology
###############################################################################
#
# Defined as a list of objects rather than separate controlplane/worker lists
# so the libvirt domain block can be a single for_each. The first controlplane
# in the list is the bootstrap node (talosctl convention).
#
# Default is the slam-stack target: a single 8 GB control plane.

variable "nodes" {
  type = list(object({
    name     = string # libvirt domain name + Talos hostname
    role     = string # "controlplane" or "worker"
    vcpu     = number # logical CPUs (SMT counts)
    memory   = number # MiB
    disk_gib = number # OS disk size
    ip       = string # last octet as a string ("11" → .11 in network_cidr)
    mac      = string # 52:54:00:00:00:XX — qemu-assigned range
  }))
  description = "Talos nodes. Default is a single 8 GB control plane (slam-stack target)."

  default = [
    { name = "slam-cp1", role = "controlplane", vcpu = 4, memory = 8192, disk_gib = 60, ip = "11", mac = "52:54:00:00:13:11" },
  ]
}

###############################################################################
# VM hardware
###############################################################################

variable "cpu_mode" {
  type        = string
  description = "libvirt CPU mode. host-passthrough exposes the host CPU verbatim — required for Talos to detect virtualization extensions and for Cilium's eBPF datapath."
  default     = "host-passthrough"
}

variable "machine_type" {
  type        = string
  description = "QEMU machine type. q35 is required for UEFI + Secure Boot."
  default     = "q35"
}

variable "boot_mode" {
  type        = string
  description = "Boot mode: 'uefi' (default, OVMF), 'uefi-secureboot' (+ swtpm TPM 2.0 + SMM), or 'bios' (SeaBIOS legacy)."
  default     = "uefi"

  validation {
    condition     = contains(["uefi", "uefi-secureboot", "bios"], var.boot_mode)
    error_message = "boot_mode must be one of: uefi, uefi-secureboot, bios."
  }
}

variable "ovmf_code_path" {
  type        = map(string)
  description = "OVMF CODE (read-only loader) firmware paths, keyed by boot_mode. Defaults target Ubuntu/Debian's ovmf package."
  default = {
    "uefi"            = "/usr/share/OVMF/OVMF_CODE_4M.fd"
    "uefi-secureboot" = "/usr/share/OVMF/OVMF_CODE_4M.secboot.fd"
  }
}

variable "ovmf_vars_template_path" {
  type        = string
  description = "OVMF VARS template. Each VM's NVRAM file is initialized from this on first boot."
  default     = "/usr/share/OVMF/OVMF_VARS_4M.fd"
}

variable "nvram_dir" {
  type        = string
  description = "Directory for per-VM NVRAM (UEFI variable store) files. Must be writable by libvirt."
  default     = "/var/lib/libvirt/qemu/nvram"
}

variable "cache_dir" {
  type        = string
  description = "Where to cache the downloaded + converted Talos qcow2. Module-relative; safe to rm -rf to force re-download."
  default     = ".cache"
}
