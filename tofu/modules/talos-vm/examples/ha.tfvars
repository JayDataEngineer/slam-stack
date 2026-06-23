# Slam Stack — 3 control planes + 1 worker (16 GB+ RAM host).
# Use for production-like HA testing on a homelab box.

cluster_name       = "slam-stack-ha"
talos_schematic_id = "376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d683354a"
talos_version      = "v1.9.5"
kubernetes_version = "v1.32.0"
boot_mode          = "uefi"

nodes = [
  { name = "slam-cp1", role = "controlplane", vcpu = 4, memory = 8192, disk_gib = 60, ip = "11", mac = "52:54:00:00:13:11" },
  { name = "slam-cp2", role = "controlplane", vcpu = 4, memory = 8192, disk_gib = 60, ip = "12", mac = "52:54:00:00:13:12" },
  { name = "slam-cp3", role = "controlplane", vcpu = 4, memory = 8192, disk_gib = 60, ip = "13", mac = "52:54:00:00:13:13" },
  { name = "slam-w1",  role = "worker",       vcpu = 4, memory = 8192, disk_gib = 120, ip = "21", mac = "52:54:00:00:13:21" },
]
