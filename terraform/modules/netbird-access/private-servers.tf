data "netbird_peer" "private" {
  for_each = var.private_server_ips
  ip       = each.value
}

resource "netbird_group" "access" {
  for_each = var.private_access_peer_ids
  name     = "private-${each.key}"
  peers    = sort(tolist(each.value))

  lifecycle {
    prevent_destroy = true
  }
}

resource "netbird_group" "private_server" {
  for_each = var.private_server_ips
  name     = "${each.key}-server"
  peers    = [data.netbird_peer.private[each.key].id]

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  private_rules = merge(
    { for name in keys(var.private_server_ips) : "${name}-ssh" => {
      host = name, sources = ["administrators"], protocol = "tcp", ports = ["22"], port_ranges = []
    } },
    { for name in keys(var.private_server_ips) : "${name}-mosh" => {
      host = name, sources = ["administrators"], protocol = "udp", ports = [], port_ranges = [{ start = 60000, end = 61000 }]
    } },
    contains(keys(var.private_server_ips), "vps") ? {
      vps-web = {
        host = "vps", sources = ["administrators"], protocol = "tcp", ports = ["443", "9443"], port_ranges = []
      }
      vps-irc = {
        host = "vps", sources = ["administrators"], protocol = "tcp", ports = ["7000"], port_ranges = []
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
    sources       = [for role in each.value.sources : netbird_group.access[role].id]
    destinations  = [netbird_group.private_server[each.value.host].id]
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
  distribution_groups  = [netbird_group.private_server[each.key].id, netbird_group.access["administrators"].id]

  lifecycle {
    prevent_destroy = true
  }
}

resource "netbird_dns_record" "private" {
  for_each = local.private_dns
  zone_id  = netbird_dns_zone.private[each.value].id
  name     = each.key
  type     = "A"
  content  = data.netbird_peer.private[each.value].ip
  ttl      = 60

  lifecycle {
    prevent_destroy = true
  }
}

