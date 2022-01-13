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

resource "null_resource" "provision_secrets" {
  triggers = {
    local-wg_server-private_key_hash = sha256(local.wg_server.private_key)
    var-restic_repository_hash       = sha256(var.restic_repository)
    var-restic_password_hash         = sha256(var.restic_password)
    var-restic_key_id_hash           = sha256(var.restic_key_id)
    var-restic_secret_hash           = sha256(var.restic_secret)
  }

  connection {
    host    = digitalocean_droplet.www.ipv4_address
    user    = "root"
    type    = "ssh"
    timeout = "2m"
    agent   = "true"
  }

  provisioner "remote-exec" {
    inline = ["mkdir -p /var/secrets"]
  }

  provisioner "file" {
    content     = local.wg_server.private_key
    destination = "/var/secrets/wg_server_private_key"
  }

  provisioner "file" {
    content     = var.restic_repository
    destination = "/var/secrets/restic_repository"
  }
  provisioner "file" {
    content     = var.restic_password
    destination = "/var/secrets/restic_password"
  }
  provisioner "file" {
    content     = <<-EOT
      B2_ACCOUNT_ID=${var.restic_key_id}
      B2_ACCOUNT_KEY=${var.restic_secret}
      EOT
    destination = "/var/secrets/restic_environment"
  }
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
      "nix-channel --add https://nixos.org/channels/nixos-20.03 nixos",
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

resource "null_resource" "nixos_rebuild" {
  depends_on = [
    null_resource.provision_secrets,
    null_resource.provision_wg_keys,
    null_resource.nixos_set_channel
  ]

  triggers = {
    droplet_id           = digitalocean_droplet.www.id
    provision_wg_keys_id = null_resource.provision_wg_keys.id
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

  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/secrets.nix",
      {
        password         = var.nix_znc_password,
        nickservPassword = var.nix_znc_nickservpassword
        hash             = var.nix_znc_hash,
        salt             = var.nix_znc_salt
      }
    )
    destination = "/etc/nixos/secrets.nix"
  }

  provisioner "remote-exec" {
    inline = ["nixos-rebuild switch"]
  }
}
