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

variable "flavor" {
  description = "Deployment flavor: core, og, or matrix"
  type        = string
  default     = "og"

  validation {
    condition     = contains(["core", "og", "matrix"], var.flavor)
    error_message = "Flavor must be one of: core, og, matrix."
  }
}

variable "domain" {
  description = "Base domain for TLS certificates"
  type        = string
  default     = "slam.lab"
}

variable "node_ip" {
  description = "IP address of the single controlplane node"
  type        = string
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
  default     = "https://github.com/your-org/slam-stack.git"
}

variable "git_branch" {
  description = "Git branch for Flux bootstrap"
  type        = string
  default     = "master"
}
