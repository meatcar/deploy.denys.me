data "digitalocean_image" "nixos" {
  name = "nixos-19.09"
}

resource "digitalocean_droplet" "www" {
  image              = data.digitalocean_image.nixos.id
  name               = var.hostname
  region             = "tor1"
  size               = "s-1vcpu-1gb"

  ssh_keys = [ var.ssh_fingerprint ]
}

resource "null_resource" "nixos_set_channel" {
  connection {
    host    = digitalocean_droplet.www.ipv4_address
    user    = "root"
    type    = "ssh"
    timeout = "2m"
    agent   = "true"
  }

  provisioner "remote-exec" {
    inline = [
      "nix-channel --remove nixos",
      "nix-channel --add https://nixos.org/channels/nixos-21.11 nixos",
      "nix-channel --update"
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "echo rebooting",
      "reboot"
    ]
    on_failure = continue
  }
}

resource "null_resource" "nixos_push" {
  depends_on = [
    null_resource.nixos_set_channel
  ]

  triggers = {
    droplet_id           = digitalocean_droplet.www.id
    hashes               = join(" ", [for f in fileset(path.module, "nixos/*") : filesha256("${path.module}/${f}")])
  }

  connection {
    host    = digitalocean_droplet.www.ipv4_address
    user    = "meatcar"
    type    = "ssh"
    timeout = "2m"
    agent   = "true"
  }

  provisioner "file" {
    source      = "${path.module}/nixos/"
    destination = "/etc/nixos"
  }

  # TODO: run nixos-rebuild switch --target-host locally
}
