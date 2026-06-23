# Slam Stack — single-node Talos VM (8 GB RAM target).
# Default flavor: use the bare metal schematic for the latest Talos minor.

cluster_name       = "slam-stack"
talos_schematic_id = "376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d683354a"
talos_version      = "v1.9.5"
kubernetes_version = "v1.32.0"
boot_mode          = "uefi"

nodes = [
  { name = "slam-cp1", role = "controlplane", vcpu = 4, memory = 8192, disk_gib = 60, ip = "11", mac = "52:54:00:00:13:11" },
]
