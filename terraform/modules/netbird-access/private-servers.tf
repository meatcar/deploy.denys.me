data "netbird_peer" "private" {
  for_each = var.private_server_ips
  ip       = each.value
}

resource "netbird_peer" "private" {
  for_each                      = var.private_server_ips
  id                            = data.netbird_peer.private[each.key].id
  name                          = each.key
  ssh_enabled                   = false
  login_expiration_enabled      = false
  inactivity_expiration_enabled = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "netbird_group" "server" {
  for_each = var.private_server_ips
  name     = "server-${each.key}"
  peers    = [netbird_peer.private[each.key].id]

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  private_rules = merge(
    { for name in keys(var.private_server_ips) : "${name}-ssh" => {
      host = name, protocol = "tcp", ports = ["22"], port_ranges = []
    } },
    { for name in keys(var.private_server_ips) : "${name}-mosh" => {
      host = name, protocol = "udp", ports = [], port_ranges = [{ start = 60000, end = 61000 }]
    } },
    contains(keys(var.private_server_ips), "vps") ? {
      vps-web = {
        host = "vps", protocol = "tcp", ports = ["443", "9443"], port_ranges = []
      }
      vps-irc = {
        host = "vps", protocol = "tcp", ports = ["7000"], port_ranges = []
      }
    } : {},
  )
  private_dns = contains(keys(var.private_server_ips), "vps") ? { "znc.denys.me" = "vps" } : {}
}

resource "netbird_policy" "private" {
  for_each = local.private_rules
  name     = each.key
  enabled  = true

  rule {
    name          = each.key
    enabled       = true
    action        = "accept"
    bidirectional = false
    protocol      = each.value.protocol
    ports         = length(each.value.ports) == 0 ? null : each.value.ports
    port_ranges   = length(each.value.port_ranges) == 0 ? null : each.value.port_ranges
    sources       = [netbird_group.role_admins.id]
    destinations  = [netbird_group.server[each.value.host].id]
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "netbird_dns_zone" "private" {
  for_each             = var.private_server_ips
  name                 = "Private ${each.key}"
  domain               = "znc.denys.me"
  enabled              = true
  enable_search_domain = false
  distribution_groups  = [netbird_group.server[each.key].id, netbird_group.role_admins.id]

  lifecycle {
    prevent_destroy = true
  }
}

resource "netbird_dns_record" "private" {
  for_each = local.private_dns
  zone_id  = netbird_dns_zone.private[each.value].id
  name     = each.key
  type     = "A"
  content  = netbird_peer.private[each.value].ip
  ttl      = 60

  lifecycle {
    prevent_destroy = true
  }
}

