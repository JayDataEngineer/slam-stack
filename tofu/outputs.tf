output "kubeconfig_path" {
  description = "Path to the cluster kubeconfig"
  value       = local_file.kubeconfig.filename
}

output "cluster_name" {
  description = "Cluster name"
  value       = var.cluster_name
}

output "flavor" {
  description = "Deployed flavor"
  value       = var.flavor
}

output "flux_sync_path" {
  description = "Flux sync path in the Git repository"
  value       = "clusters/${var.flavor}"
}
