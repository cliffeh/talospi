# talospi

A Terraform module for maintaining a talos installation on a cluster of Raspberry Pis.

## Getting Started

You may wish to generate and store your own secrets using `talosctl gen secrets` and
pass them in as the variable `secrets_file`. If no secrets are passed in, they will be
generated for you.

Providing `secrets_file` is strongly recommended: the secrets are what let Terraform talk to
nodes that are already configured, so with them you can recover from lost state by applying
again (see [Lost Terraform state](#lost-terraform-state)). Generated secrets exist only in
Terraform state.

## Nodes and extensions

Nodes are declared in the `nodes` map. Each node's `model` (`rpi4` or `rpi5`) selects the
Image Factory overlay (`rpi_generic` or `rpi_5`). Extensions in `default_extensions` apply to
every node; setting `extensions` on a node replaces the defaults for that node.

```hcl
default_extensions = ["siderolabs/iscsi-tools", "siderolabs/util-linux-tools"]

nodes = {
  cp1 = { address = "10.0.0.11", role = "controlplane", model = "rpi5" }
  w1  = { address = "10.0.0.21", role = "worker", model = "rpi4" }
  w2 = {
    address      = "10.0.0.22"
    role         = "worker"
    model        = "rpi5"
    install_disk = "/dev/nvme0n1"
    extensions   = ["siderolabs/iscsi-tools"] # replaces default_extensions
  }
}
```

One schematic is created per unique model + extension set. The `nodes` output gives each node's
`disk_image` URL to flash to its boot media before running `terraform apply`.

Nodes are managed with `talos_machine`, which applies the machine config and keeps the OS
in sync with the node's installer image: changing `talos_version` or a node's extensions
upgrades (and reboots) that node on the next apply. Control plane nodes are applied before
workers, but nodes within each group are upgraded in parallel, so use
`terraform apply -parallelism=1` for upgrades that should roll one node at a time.

Set `kubeconfig` to have nodes drained before an upgrade reboot and uncordoned afterwards.

## Lifecycle

### Building from scratch

New nodes need to be flashed with the right image before Terraform can configure them, so
build the images first:

```sh
terraform apply -target=data.talos_image_factory_urls.this
terraform output nodes   # each node's disk_image URL
```

Flash each node's `disk_image` to the boot media matching its `install_disk`, boot it, and
wait for it to reach maintenance mode. Then run `terraform apply`. Nodes in maintenance mode
accept their first configuration without client certificates; if a node was flashed with a
different Talos version or extensions than it's configured for, it is upgraded to match
(an extra reboot).

**CAVEAT:** Bootstrapping (`talosctl bootstrap`) is not included (yet) and needs to be done manually.

### Adding nodes to an existing cluster

Add the node to `nodes`, then follow the same steps: apply with `-target` to get its image,
flash and boot it, then run a full `terraform apply`.

### Rebuilding a node that is already in state

If a node's boot media is reflashed or replaced, Terraform will not notice: it can't read a
configuration from the wiped node, so it keeps the one recorded in state and plans no
changes, leaving the node in maintenance mode. Force the node to be configured again:

```sh
terraform apply -replace='talos_machine.worker["w1"]'        # or talos_machine.controlplane["..."]
```

Flash it with its `disk_image` from `terraform output nodes` first, as for a new node.

Before rebuilding a control plane node in a cluster that has other control plane nodes,
remove its old etcd member from a healthy control plane node, or it can't rejoin:

```sh
talosctl -n <healthy-cp> etcd members
talosctl -n <healthy-cp> etcd remove-member <member-id>
```

### Removing a node

Delete it from `nodes` and apply. This only removes the node from Terraform; the machine
keeps running its configuration until it is reset (`talosctl reset`) or powered off.

### Lost Terraform state

With `secrets_file` set, run `terraform apply` again. The secrets are imported, the image
schematics are recreated (Image Factory returns the same IDs for the same content), and
already-configured nodes are reached with the client certificates derived from the secrets
and re-applied in place. Nodes already on the right image are not upgraded.
