###############################################################################
# Outputs — consumed by the parent tofu stack or directly by talosctl
###############################################################################

output "cluster_name" {
  value = var.cluster_name
}

output "talos_schematic_id" {
  value = var.talos_schematic_id
}

output "talos_version" {
  value = var.talos_version
}

output "kubernetes_version" {
  value = var.kubernetes_version
}

output "network_cidr" {
  value = var.network_cidr
}

output "gateway_ip" {
  value = local.gateway_ip
}

output "control_plane_ips" {
  value       = local.controlplane_ips
  description = "Pass to talosctl apply-config. The first entry is the bootstrap node."
}

output "worker_ips" {
  value       = local.worker_ips
  description = "Empty list if running a control-plane-only cluster."
}

output "bootstrap_node_ip" {
  value       = local.bootstrap_ip
  description = "First control plane. Pass to `talosctl bootstrap --nodes <ip>`."
}

output "expected_node_ips_by_mac" {
  value       = { for n in var.nodes : n.mac => "${local.network_prefix}.${n.ip}" }
  description = "Intended MAC→IP mapping. Verify against `virsh net-dhcp-leases` via scripts/discover-ips.sh."
}

output "all_node_ips_by_name" {
  value = local.node_ips
}

output "talos_api_endpoint" {
  value       = "${local.bootstrap_ip}:50000"
  description = "Bootstrap node's Talos API endpoint. Pass to CLUSTER_API_ENDPOINT."
}
