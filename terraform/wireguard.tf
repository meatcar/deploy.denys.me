variable "working_directory" {
  type        = string
  description = "Original Terraform root directory for generated WireGuard files outside the Terragrunt cache."
  default     = "."
}

resource "random_id" "wg_priv_keys" {
  for_each = toset(var.wg_nodes)

  keepers = {
    node = each.key
  }

  byte_length = 32
}

data "external" "wg_keys" {
  for_each = toset(var.wg_nodes)
  program  = ["bin/make-wg-key", sensitive(random_id.wg_priv_keys[each.key].b64_std)]
}

locals {
  wg_peers = {
    for i, node in var.wg_nodes :
    node => {
      name        = node
      public_key  = data.external.wg_keys[node].result.public_key
      private_key = data.external.wg_keys[node].result.private_key
      ip          = "10.100.0.${i + 1}"
    }
  }
  wg_server  = merge(local.wg_peers["server"], { name = var.hostname })
  wg_clients = { for k, v in local.wg_peers : k => v if k != "server" }
}

resource "local_file" "generate_wg_nixos_config" {
  filename        = abspath("${var.working_directory}/../nixos/generated/wg-clients.nix")
  file_permission = "0640"
  content = templatefile(
    "${path.module}/templates/wg-clients.nix.tmpl",
    {
      clients = local.wg_clients
  })
}

resource "local_sensitive_file" "wg_client_config" {
  for_each = local.wg_clients

  filename        = abspath("${var.working_directory}/output/wg-${local.wg_clients[each.key].name}.conf")
  file_permission = "0640"
  content = templatefile(
    "${path.module}/templates/wireguard-client.conf",
    {
      server = local.wg_server
      client = local.wg_clients[each.key]
  })

}
