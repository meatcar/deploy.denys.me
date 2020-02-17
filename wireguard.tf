# hack, generate wg private keys manually, to keep the keys from changing on refresh
resource "random_id" "wg_priv_keys" {
  count = length(var.wg_nodes)

  keepers = {
    node = var.wg_nodes[count.index]
  }

  byte_length = 32
}

data "external" "wg_keys" {
  count   = length(var.wg_nodes)
  program = ["bin/make-wg-key", random_id.wg_priv_keys[count.index].b64_std]
}

locals {
  wg_peers = [
    for i in range(length(var.wg_nodes)) :
    {
      name        = var.wg_nodes[i]
      public_key  = data.external.wg_keys[i].result.public_key
      private_key = data.external.wg_keys[i].result.private_key
      ip          = "10.100.0.${i + 1}"
    }
  ]
  wg_server  = merge(local.wg_peers[0], { name = var.hostname })
  wg_clients = slice(local.wg_peers, 1, length(local.wg_peers))
}

resource "null_resource" "provision_wg_keys" {
  triggers = {
    droplet_id = digitalocean_droplet.www.id
    wg_ips     = join(",", local.wg_peers.*.ip)
    wg_pub_ks  = join(",", local.wg_peers.*.public_key)
  }

  connection {
    host    = digitalocean_droplet.www.ipv4_address
    user    = "root"
    type    = "ssh"
    timeout = "2m"
    agent   = "true"
  }

  provisioner "file" {
    content     = local.wg_server.private_key
    destination = "/var/secrets/wg_server_private_key"
  }

  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/wg-clients.nix.tmpl",
    { clients = local.wg_clients })
    destination = "/etc/nixos/wg-clients.nix"
  }
}

resource "local_file" "wg_client_config" {
  count = length(var.wg_nodes) - 1 # don't generate server's config

  filename        = "${path.module}/output/wg-${local.wg_clients[count.index].name}.conf"
  file_permission = "0640"
  sensitive_content = templatefile(
    "${path.module}/templates/wireguard-client.conf",
    {
      server = local.wg_server
      client = local.wg_clients[count.index]
  })

}
