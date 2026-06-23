###############################################################################
# Locals — derived values used across resources
###############################################################################

locals {
  network_parts  = split(".", cidrhost(var.network_cidr, 0))
  network_prefix = join(".", slice(local.network_parts, 0, 3))
  gateway_ip     = "${local.network_prefix}.1"
  dns_ip         = local.gateway_ip # libvirt's built-in dnsmasq

  node_ips = { for n in var.nodes : n.name => "${local.network_prefix}.${n.ip}" }

  net_name  = "${var.cluster_name}-${var.network_name}"
  pool_name = "${var.cluster_name}-pool"
  base_vol  = "${var.cluster_name}-talos-${var.talos_version}-${var.cpu_arch}"

  bootstrap_node = [for n in var.nodes : n if n.role == "controlplane"][0]
  bootstrap_ip   = local.node_ips[local.bootstrap_node.name]

  controlplane_ips = [for n in var.nodes : local.node_ips[n.name] if n.role == "controlplane"]
  worker_ips       = [for n in var.nodes : local.node_ips[n.name] if n.role == "worker"]
}

###############################################################################
# Talos image cache — download once per (schematic, version, arch)
###############################################################################

resource "null_resource" "talos_image" {
  triggers = {
    schematic = var.talos_schematic_id
    version   = var.talos_version
    arch      = var.cpu_arch
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/fetch-talos-image.sh ${var.talos_schematic_id} ${var.talos_version} ${var.cpu_arch} ${path.module}/${var.cache_dir}"
  }

  lifecycle {
    prevent_destroy = false
  }
}

###############################################################################
# libvirt storage pool
###############################################################################

resource "libvirt_pool" "talos" {
  name = local.pool_name
  type = "dir"
  path = "/var/lib/libvirt/images/${local.pool_name}"
}

###############################################################################
# Base volume — the Talos qcow2 fetched above
###############################################################################

resource "libvirt_volume" "talos_base" {
  depends_on = [null_resource.talos_image]

  name   = "${local.base_vol}.qcow2"
  pool   = libvirt_pool.talos.name
  source = "${path.module}/${var.cache_dir}/talos-${var.talos_version}-${var.cpu_arch}.qcow2"
  format = "qcow2"
}

###############################################################################
# Per-node volumes — qcow2 backed by the base (copy-on-write)
###############################################################################

resource "libvirt_volume" "node_disk" {
  for_each = { for n in var.nodes : n.name => n }

  name           = "${var.cluster_name}-${each.value.name}.qcow2"
  pool           = libvirt_pool.talos.name
  base_volume_id = libvirt_volume.talos_base.id
  size           = each.value.disk_gib * 1024 * 1024 * 1024
  format         = "qcow2"
}

###############################################################################
# Network — NAT with DHCP MAC→IP reservations (XSLT-injected)
###############################################################################
#
# Without DHCP reservations, Talos nodes boot in maintenance mode and pull a
# RANDOM lease (.146, .147, etc.) — different from the static IPs talhelper
# bakes into machine configs. With reservations in place, the DHCP server
# hands each VM's MAC its STATIC IP from the very first DHCPDISCOVER.

resource "libvirt_network" "talos_net" {
  name      = local.net_name
  mode      = "nat"
  domain    = "${var.cluster_name}.local"
  addresses = [var.network_cidr]

  dns {
    enabled    = true
    local_only = true
  }

  dhcp {
    enabled = true
  }

  xml {
    xslt = <<-XSLT
      <xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
        <xsl:output method="xml" indent="yes"/>
        <xsl:template match="/network/ip/dhcp">
          <xsl:copy>
            <xsl:copy-of select="@*|node()"/>
            %{for n in var.nodes~}
            <host mac="${n.mac}" name="${n.name}" ip="${local.network_prefix}.${n.ip}"/>
            %{endfor~}
          </xsl:copy>
        </xsl:template>
        <xsl:template match="@*|node()">
          <xsl:copy><xsl:apply-templates select="@*|node()"/></xsl:copy>
        </xsl:template>
      </xsl:stylesheet>
    XSLT
  }

  autostart = true
}

###############################################################################
# Domains — one per node
###############################################################################

resource "libvirt_domain" "node" {
  for_each = { for n in var.nodes : n.name => n }

  name      = "${var.cluster_name}-${each.value.name}"
  vcpu      = each.value.vcpu
  memory    = each.value.memory
  autostart = true

  machine = var.machine_type

  cpu {
    mode = var.cpu_mode
  }

  firmware = var.boot_mode == "bios" ? null : var.ovmf_code_path[var.boot_mode]

  dynamic "nvram" {
    for_each = var.boot_mode == "bios" ? [] : [1]
    content {
      file     = "${var.nvram_dir}/${var.cluster_name}-${each.value.name}_VARS.fd"
      template = var.ovmf_vars_template_path
    }
  }

  dynamic "tpm" {
    for_each = var.boot_mode == "uefi-secureboot" ? [1] : []
    content {
      backend_type    = "emulator"
      backend_version = "2.0"
      model           = "tpm-crb"
    }
  }

  dynamic "xml" {
    for_each = var.boot_mode == "uefi-secureboot" ? [1] : []
    content {
      xslt = <<-XSLT
        <xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
          <xsl:output method="xml" indent="yes"/>
          <xsl:template match="/domain">
            <xsl:copy>
              <xsl:apply-templates select="@*"/>
              <xsl:apply-templates select="node()[not(self::features)]"/>
            </xsl:copy>
          </xsl:template>
          <xsl:template match="features">
            <xsl:copy>
              <xsl:copy-of select="@*|node()"/>
              <smm state="on"/>
            </xsl:copy>
          </xsl:template>
          <xsl:template match="os/loader">
            <xsl:copy>
              <xsl:attribute name="secure">yes</xsl:attribute>
              <xsl:apply-templates select="@*|node()"/>
            </xsl:copy>
          </xsl:template>
          <xsl:template match="@*|node()">
            <xsl:copy><xsl:apply-templates select="@*|node()"/></xsl:copy>
          </xsl:template>
        </xsl:stylesheet>
      XSLT
    }
  }

  network_interface {
    network_id     = libvirt_network.talos_net.id
    mac            = each.value.mac
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.node_disk[each.value.name].id
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type        = "spice"
    autoport    = true
    listen_type = "none"
  }
}
