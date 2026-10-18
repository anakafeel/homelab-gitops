# Always-on k3s agent VM on the laptop ("self-hosted EC2"). It starts with the
# laptop and rejoins the cluster over Tailscale after every boot or resume; while
# the laptop is off the Node is just NotReady. Applied from the laptop only:
# CI can't reach the laptop's libvirt. See README.md.
terraform {
  required_version = ">= 1.10.0"

  # State in Garage, same setup as tofu/cloudflare.
  backend "s3" {
    bucket                      = "tofu-state"
    key                         = "laptop-vms/terraform.tfstate"
    region                      = "garage"
    use_path_style              = true
    use_lockfile                = true # Garage ignores it (no conditional writes)
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.9.9"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

variable "tailscale_authkey" {
  description = "Non-ephemeral, pre-approved Tailscale auth key tagged tag:lab-node (the node must survive reboots)."
  type        = string
  sensitive   = true
}

variable "k3s_token" {
  description = "Non-expiring k3s bootstrap token (`k3s token create --ttl 0` on the Pi; revoke with `k3s token delete`)."
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH key for the default 'debian' user (debugging only)."
  type        = string
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKB31181+40goO/Fey0QDfkiNQ2I/Q1Z2lggjKTKI6iJ" # laptop key, public
}

locals {
  name        = "lab-node"
  k3s_version = "v1.36.5+k3s1"               # match the server
  k3s_server  = "https://100.68.237.12:6443" # Pi's tailnet IP (in the API cert's SANs)
}

resource "libvirt_pool" "lab" {
  name = "homelab-lab"
  type = "dir"
  target = {
    path = "/var/lib/libvirt/images"
  }
}

resource "libvirt_volume" "debian" {
  name = "debian-13-genericcloud-amd64.qcow2"
  pool = libvirt_pool.lab.name
  target = {
    format = { type = "qcow2" }
  }
  create = {
    content = {
      url = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
    }
  }
}

# Copy-on-write layer over the base image; thin, grows only as written.
resource "libvirt_volume" "disk" {
  name     = "${local.name}.qcow2"
  pool     = libvirt_pool.lab.name
  capacity = 21474836480 # 20 GiB
  target = {
    format = { type = "qcow2" }
  }
  backing_store = {
    path   = libvirt_volume.debian.path
    format = { type = "qcow2" }
  }
}

resource "libvirt_cloudinit_disk" "seed" {
  name = "${local.name}-seed"
  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    hostname          = local.name
    ssh_key           = var.ssh_public_key
    tailscale_authkey = var.tailscale_authkey
    k3s_version       = local.k3s_version
    k3s_server        = local.k3s_server
    k3s_token         = var.k3s_token
  })
  meta_data = yamlencode({
    instance-id    = local.name
    local-hostname = local.name
  })
}

resource "libvirt_volume" "seed" {
  name = "${local.name}-seed.iso"
  pool = libvirt_pool.lab.name
  create = {
    content = {
      url = libvirt_cloudinit_disk.seed.path
    }
  }
}

resource "libvirt_domain" "lab" {
  name        = local.name
  type        = "kvm"
  vcpu        = 2
  memory      = 2048
  memory_unit = "MiB"
  running     = true
  autostart   = true # starts with libvirtd.service at laptop boot

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
  }

  # Without ACPI the guest can't enumerate q35's PCIe bus: no disk, no NIC.
  features = {
    acpi = true
    apic = {}
  }

  devices = {
    # `virsh console lab-node` for boot debugging.
    consoles = [
      {
        target = { type = "serial", port = 0 }
      },
    ]
    # With no video device the Debian kernel resets right after GRUB.
    videos = [
      {
        model = { type = "vga" }
      },
    ]
    disks = [
      {
        source = {
          volume = {
            pool   = libvirt_volume.disk.pool
            volume = libvirt_volume.disk.name
          }
        }
        target = { dev = "vda", bus = "virtio" }
        driver = { type = "qcow2" }
      },
      {
        device = "cdrom"
        source = {
          volume = {
            pool   = libvirt_volume.seed.pool
            volume = libvirt_volume.seed.name
          }
        }
        target = { dev = "sda", bus = "sata" }
      },
    ]
    interfaces = [
      {
        type   = "network"
        model  = { type = "virtio" }
        source = { network = { network = "default" } }
      },
    ]
  }
}

# k3s refuses a new machine reusing a node name whose password secret still
# exists, so the Node object goes away with the VM (kube context "pi").
resource "terraform_data" "node_cleanup" {
  triggers_replace = [libvirt_domain.lab.id]

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl --context pi delete node lab-node --ignore-not-found"
  }
}
