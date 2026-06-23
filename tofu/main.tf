terraform {
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.6"
    }
    flux = {
      source  = "fluxcd/flux"
      version = "~> 1.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "talos" {}

provider "flux" {
  git = {
    url    = var.git_repo_url
    branch = var.git_branch
  }
  kubernetes = {
    host                   = talos_cluster_kubeconfig.this.kubernetes_client_configuration.host
    client_certificate     = talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate
    client_key             = talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key
    cluster_ca_certificate = talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate
  }
}

# ---------------------------------------------------------------------------
# Machine secrets (unique per cluster)
# ---------------------------------------------------------------------------
resource "talos_machine_secrets" "this" {}

# ---------------------------------------------------------------------------
# Bootstrap Talos — single-node controlplane
# ---------------------------------------------------------------------------
data "talos_machine_configuration" "this" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = "https://${local.effective_node_ip}:6443"
  kubernetes_version = var.kubernetes_version
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk = var.install_disk
        }
        network = {
          hostname = var.node_hostname
        }
        kubelet = {
          extraArgs = {
            node-labels = "node-role.kubernetes.io/controlplane="
          }
        }
      }
      cluster = {
        allowSchedulingOnControlPlanes = true
        apiServer = {
          extraArgs = {
            oidc-issuer-url     = "https://kanidm.identity.svc.cluster.local/oauth2/openid/slam-stack"
            oidc-client-id      = "slam-stack"
            oidc-username-claim = "preferred_username"
            oidc-groups-claim   = "groups"
          }
        }
      }
    })
  ]
}

resource "talos_machine_configuration_apply" "this" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this.machine_configuration
  node                        = local.effective_node_ip
  config_patches              = []
}

resource "talos_machine_bootstrap" "this" {
  depends_on           = [talos_machine_configuration_apply.this]
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.effective_node_ip
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on           = [talos_machine_bootstrap.this]
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.effective_node_ip
}

# ---------------------------------------------------------------------------
# Bootstrap Flux
# ---------------------------------------------------------------------------
resource "flux_bootstrap_git" "this" {
  depends_on = [talos_cluster_kubeconfig.this]
  path       = "clusters/${var.flavor}"
}

# ---------------------------------------------------------------------------
# Write kubeconfig locally
# ---------------------------------------------------------------------------
resource "local_file" "kubeconfig" {
  depends_on      = [talos_cluster_kubeconfig.this]
  content         = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename        = pathexpand("~/.kube/${var.cluster_name}-config")
  file_permission = "0600"
}
