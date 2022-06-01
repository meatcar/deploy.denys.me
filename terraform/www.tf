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
      "nix-channel --add https://nixos.org/channels/nixos-22.05 nixos",
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
