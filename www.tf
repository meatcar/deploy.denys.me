data "digitalocean_image" "nixos" {
  name = "nixos-19.09"
}

resource "digitalocean_droplet" "www" {
  image              = data.digitalocean_image.nixos.id
  name               = var.hostname
  region             = "tor1"
  size               = "s-1vcpu-1gb"
  private_networking = false

  ssh_keys = [
    "${var.ssh_fingerprint}",
  ]
}

resource "null_resource" "nixos_rebuild" {
  depends_on = [null_resource.provision_wg_keys]
  triggers = {
    droplet_id           = digitalocean_droplet.www.id
    provision_wg_keys_id = null_resource.provision_wg_keys.id
    hashes               = join(" ", [for f in fileset("${path.module}", "nix/*") : filesha256("${path.module}/${f}")])
  }

  connection {
    host    = digitalocean_droplet.www.ipv4_address
    user    = "root"
    type    = "ssh"
    timeout = "2m"
    agent   = "true"
  }

  provisioner "file" {
    source      = "${path.module}/nix/"
    destination = "/etc/nixos"
  }

  provisioner "remote-exec" {
    inline = ["nixos-rebuild switch"]
  }

  provisioner "remote-exec" {
    inline = [
      "echo rebooting",
      "reboot"
    ]
    on_failure = continue
  }
}
