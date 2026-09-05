resource "digitalocean_droplet" "www" {
  image  = "56524328"
  name   = var.hostname
  region = "tor1"
  size   = "s-1vcpu-1gb"

  ssh_keys = [var.ssh_fingerprint]
}

removed {
  from = null_resource.nixos_set_channel

  lifecycle {
    destroy = false
  }
}
