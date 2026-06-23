# =============================================================================
# Slam Stack — Optional libvirt VM provisioning
# =============================================================================
#
# Drop-in use of the talos-vm module. Enable by setting `create_vms = true`
# in terraform.tfvars. When false (default), this file is a no-op and the
# parent stack assumes Talos nodes already exist.
#
# Flow:
#   1. `create_vms = true` → this module provisions VMs in libvirt
#   2. The vm outputs feed the parent's talos_machine_configuration_apply
#   3. `create_vms = false` → skip; user provides node_ip via var.node_ip
# =============================================================================

variable "create_vms" {
  type        = bool
  description = "Set true to provision libvirt VMs via the talos-vm module. When false (default), the stack assumes Talos nodes already exist."
  default     = false
}

variable "talos_schematic_id" {
  type        = string
  description = "Talos schematic ID for factory.talos.dev image. Required when create_vms = true."
  default     = "376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d683354a"
}

variable "boot_mode" {
  type        = string
  description = "VM firmware mode when create_vms = true. One of: uefi, uefi-secureboot, bios."
  default     = "uefi"

  validation {
    condition     = contains(["uefi", "uefi-secureboot", "bios"], var.boot_mode)
    error_message = "boot_mode must be one of: uefi, uefi-secureboot, bios."
  }
}

variable "libvirt_uri" {
  type        = string
  description = "libvirt connection URI used when create_vms = true. Default targets the local system libvirt daemon. For a remote hypervisor: qemu+ssh://user@host/system."
  default     = "qemu:///system"
}

# Provider config lives at the parent level so the module can be called with
# `count` (legacy modules with their own provider blocks forbid that).
provider "libvirt" {
  alias = "vm"
  uri   = var.libvirt_uri
}

module "talos_vms" {
  count  = var.create_vms ? 1 : 0
  source = "./modules/talos-vm"

  providers = {
    libvirt = libvirt.vm
    null    = null
    local   = local
  }

  cluster_name       = var.cluster_name
  talos_schematic_id = var.talos_schematic_id
  talos_version      = var.talos_version
  boot_mode          = var.boot_mode
}

# When we created the VMs, override node_ip with the bootstrap node IP
# so the parent stack's talos_machine_configuration_apply targets it.
locals {
  effective_node_ip = var.create_vms ? module.talos_vms[0].bootstrap_node_ip : var.node_ip
}
