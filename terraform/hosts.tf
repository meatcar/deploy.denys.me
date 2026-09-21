resource "digitalocean_droplet" "www" {
  image  = "56524328"
  name   = var.hostname
  region = "tor1"
  size   = "s-1vcpu-1gb"

  ssh_keys = [var.ssh_fingerprint]
}

module "chunkymonkey" {
  source = "./modules/oci-host"

  oci_compartment_ocid = var.oci_compartment_ocid
}

resource "ovh_vps" "bao" {
  # NOTE: The provider imports an empty purchase plan, not null.
  plan = []

  lifecycle {
    prevent_destroy = true
  }
}

removed {
  from = null_resource.nixos_set_channel

  lifecycle {
    destroy = false
  }
}
