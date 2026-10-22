output "talosconfig" {
  description = "talosctl client configuration for the cluster"
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "nodes" {
  description = "Per-node schematic and image details; flash `disk_image` to the node's boot media before applying config"
  value = {
    for name, node in local.nodes : name => {
      address      = node.address
      role         = node.role
      model        = node.model
      extensions   = node.extensions
      schematic_id = talos_image_factory_schematic.this[local.node_schematic_keys[name]].id
      disk_image   = data.talos_image_factory_urls.this[local.node_schematic_keys[name]].urls.disk_image
      installer    = local.node_installers[name]
    }
  }
}
