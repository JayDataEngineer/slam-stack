###############################################################################
# Provider requirements
###############################################################################
#
# The libvirt provider configuration lives in the parent stack so the
# module can be invoked with count/for_each (legacy modules with their
# own provider blocks forbid that). The parent must pass `providers`
# when calling this module:
#
#   module "talos_vms" {
#     source = "./modules/talos-vm"
#     providers = {
#       libvirt = libvirt
#       null    = null
#       local   = local
#     }
#   }

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
