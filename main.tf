
locals {
  # Image Factory overlay names for each supported board.
  overlays = {
    rpi4 = "rpi_generic"
    rpi5 = "rpi_5"
  }

  # Resolve each node's effective extension list: a per-node list replaces the defaults.
  nodes = {
    for name, node in var.nodes : name => merge(node, {
      hostname   = coalesce(node.hostname, name)
      extensions = sort(distinct(node.extensions != null ? node.extensions : var.default_extensions))
    })
  }

  # One schematic per unique (model, extensions) combination, so nodes with
  # identical hardware and extensions share an image.
  node_schematic_keys = {
    for name, node in local.nodes : name => "${node.model}:${join(",", node.extensions)}"
  }

  schematics = {
    for name, node in local.nodes : local.node_schematic_keys[name] => {
      model      = node.model
      extensions = node.extensions
    }...
  }
}

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

import {
  for_each = var.secrets_file != "" ? { secrets = var.secrets_file } : {}
  id       = var.secrets_file
  to       = talos_machine_secrets.this
}

resource "talos_image_factory_schematic" "this" {
  for_each = local.schematics

  schematic = templatefile("${path.module}/templates/schematic.yaml.tftpl", {
    overlay    = local.overlays[each.value[0].model]
    extensions = each.value[0].extensions
  })
}

data "talos_image_factory_urls" "this" {
  for_each = local.schematics

  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.this[each.key].id
  architecture  = "arm64"
  sbc           = local.overlays[each.value[0].model]
}

data "talos_machine_configuration" "this" {
  for_each = local.nodes

  cluster_name     = var.cluster_name
  cluster_endpoint = var.cluster_endpoint
  machine_type     = each.value.role
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version

  config_patches = concat([
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "UnattendedInstallConfig"
      installer = {
        image = local.node_installers[each.key]
      }
      provisioning = {
        diskSelector = {
          match = "disk.dev_path == \"${each.value.install_disk}\""
        }
      }
    }),
    # The generated config sets `auto: stable`, which can't coexist with a static hostname.
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      auto       = "off"
      hostname   = each.value.hostname
    }),
  ], each.value.config_patches)
}

locals {
  node_installers = {
    for name, key in local.node_schematic_keys : name => data.talos_image_factory_urls.this[key].urls.installer
  }
}

# Control plane and worker nodes are separate resources so that workers are only
# configured (and upgraded) after every control plane node has finished.
resource "talos_machine" "controlplane" {
  for_each = { for name, node in local.nodes : name => node if node.role == "controlplane" }

  node                  = each.value.address
  client_configuration  = talos_machine_secrets.this.client_configuration
  machine_configuration = data.talos_machine_configuration.this[each.key].machine_configuration
  # Upgrades the node when the Talos version or Image Factory schematic differs.
  image            = local.node_installers[each.key]
  drain_on_upgrade = nonsensitive(var.kubeconfig != null)
  kubeconfig       = var.kubeconfig
}

resource "talos_machine" "worker" {
  for_each = { for name, node in local.nodes : name => node if node.role == "worker" }

  node                  = each.value.address
  client_configuration  = talos_machine_secrets.this.client_configuration
  machine_configuration = data.talos_machine_configuration.this[each.key].machine_configuration
  image                 = local.node_installers[each.key]
  drain_on_upgrade      = nonsensitive(var.kubeconfig != null)
  kubeconfig            = var.kubeconfig

  depends_on = [talos_machine.controlplane]
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [for n in local.nodes : n.address if n.role == "controlplane"]
  nodes                = [for n in local.nodes : n.address]
}
