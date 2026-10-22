variable "talos_version" {
  description = "Talos version to use"
  type        = string
  default     = "v1.14.4"
}

variable "secrets_file" {
  description = "Path to the secrets file; if none provided, secrets will be generated"
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "A name to provide for the Talos cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = "The endpoint for the Talos cluster"
  type        = string
}

variable "default_extensions" {
  description = "Official Talos system extensions (e.g. \"siderolabs/iscsi-tools\") installed on every node that does not set its own `extensions`"
  type        = list(string)
  default     = []
}

variable "nodes" {
  description = <<-EOT
    Map of nodes in the cluster, keyed by name. The key is used as the hostname unless `hostname` is set.

    - address:        IP or DNS name used to reach the node's Talos API
    - role:           "controlplane" or "worker"
    - model:          "rpi4" or "rpi5"
    - hostname:       optional static hostname (defaults to the map key)
    - install_disk:   device Talos is installed to (defaults to the SD card, /dev/mmcblk0)
    - extensions:     optional list of extensions; when set it REPLACES `default_extensions` for this node
    - config_patches: optional extra machine config patches (YAML strings) for this node
  EOT
  type = map(object({
    address        = string
    role           = string
    model          = string
    hostname       = optional(string)
    install_disk   = optional(string, "/dev/mmcblk0")
    extensions     = optional(list(string))
    config_patches = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for n in values(var.nodes) : contains(["controlplane", "worker"], n.role)])
    error_message = "Each node's role must be \"controlplane\" or \"worker\"."
  }

  validation {
    condition     = alltrue([for n in values(var.nodes) : contains(["rpi4", "rpi5"], n.model)])
    error_message = "Each node's model must be \"rpi4\" or \"rpi5\"."
  }
}

variable "kubeconfig" {
  description = "Kubeconfig used to drain and uncordon nodes during Talos upgrades; when null, nodes are upgraded without draining"
  type        = string
  default     = null
  sensitive   = true
}
