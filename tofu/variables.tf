variable "cluster_name" {
  description = "Talos cluster name"
  type        = string
  default     = "slam-stack"
}

variable "talos_version" {
  description = "Talos version for machine config"
  type        = string
  default     = "v1.9"
}

variable "kubernetes_version" {
  description = "Kubernetes version baked into the Talos image"
  type        = string
  default     = "v1.32.0"
}

variable "flavor" {
  description = "Deployment flavor: minimal, core, og, matrix, commet, or rust"
  type        = string
  default     = "og"

  validation {
    condition     = contains(["minimal", "core", "og", "matrix", "commet", "rust"], var.flavor)
    error_message = "Flavor must be one of: minimal, core, og, matrix, commet, rust."
  }
}

variable "domain" {
  description = "Base domain for TLS certificates"
  type        = string
  default     = "slam.lab"
}

variable "node_ip" {
  description = "IP address of the single controlplane node. Optional when create_vms = true (the libvirt module provides it)."
  type        = string
  default     = null
}

variable "node_hostname" {
  description = "Hostname of the node"
  type        = string
  default     = "slam-node"
}

variable "install_disk" {
  description = "Disk device for Talos install (e.g. /dev/sda or /dev/nvme0n1)"
  type        = string
  default     = "/dev/sda"
}

variable "git_repo_url" {
  description = "Git repository URL for Flux bootstrap"
  type        = string
  default     = "https://github.com/JayDataEngineer/slam-stack.git"
}

variable "git_branch" {
  description = "Git branch for Flux bootstrap"
  type        = string
  default     = "master"
}
