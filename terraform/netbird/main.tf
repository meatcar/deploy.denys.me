data "netbird_peers" "bao" {
  ip = "10.201.219.143"
}

data "netbird_peers" "chunkymonkey" {
  ip = "10.201.92.223"
}

data "netbird_group" "bao_admins" {
  name = "bao-admins"
}

data "netbird_group" "bao_server" {
  name = "bao-server"
}

resource "netbird_peer" "bao" {
  id                            = one(data.netbird_peers.bao.ids)
  name                          = "bao"
  ssh_enabled                   = false
  login_expiration_enabled      = false
  inactivity_expiration_enabled = false

  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = length(data.netbird_peers.bao.ids) == 1
      error_message = "Exactly one enrolled Bao peer must match the pinned VPN address."
    }
  }
}

resource "netbird_peer" "chunkymonkey" {
  id                            = one(data.netbird_peers.chunkymonkey.ids)
  name                          = "chunkymonkey"
  ssh_enabled                   = false
  login_expiration_enabled      = false
  inactivity_expiration_enabled = false

  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = length(data.netbird_peers.chunkymonkey.ids) == 1
      error_message = "Exactly one enrolled chunkymonkey peer must match the pinned VPN address."
    }
  }
}

resource "netbird_group" "bao_admins" {
  name  = "bao-admins"
  peers = sort(tolist(var.bao_admin_peer_ids))

  lifecycle {
    prevent_destroy = true
  }
}

resource "netbird_group" "bao_server" {
  name  = "bao-server"
  peers = [netbird_peer.bao.id]

  lifecycle {
    prevent_destroy = true
  }
}

resource "netbird_group" "cpa_admins" {
  name  = "cpa-admins"
  peers = sort(tolist(var.cpa_admin_peer_ids))

  lifecycle {
    prevent_destroy = true
  }
}

resource "netbird_group" "cpa_server" {
  name  = "cpa-server"
  peers = [netbird_peer.chunkymonkey.id]

  lifecycle {
    prevent_destroy = true
  }
}

resource "netbird_policy" "bao" {
  name    = "bao-admin-access"
  enabled = true

  rule {
    name          = "OpenBao HTTPS"
    enabled       = true
    action        = "accept"
    bidirectional = false
    protocol      = "tcp"
    ports         = ["443"]
    sources       = [netbird_group.bao_admins.id]
    destinations  = [netbird_group.bao_server.id]
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "netbird_policy" "cpa" {
  name    = "cpa-admin-access"
  enabled = true

  rule {
    name          = "CPA management HTTPS"
    enabled       = true
    action        = "accept"
    bidirectional = false
    protocol      = "tcp"
    # NOTE: NetBird checks ingress before and after the host redirects 443 to 9443.
    ports        = ["443", "9443"]
    sources      = [netbird_group.cpa_admins.id]
    destinations = [netbird_group.cpa_server.id]
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "netbird_dns_zone" "bao" {
  name                 = var.bao_dns_zone_name
  domain               = "bao.vpn.denys.me"
  enabled              = true
  enable_search_domain = false
  distribution_groups  = [netbird_group.bao_admins.id, netbird_group.bao_server.id]

  lifecycle {
    prevent_destroy = true
  }
}

resource "netbird_dns_record" "bao" {
  zone_id = netbird_dns_zone.bao.id
  name    = "bao.vpn.denys.me"
  type    = "A"
  content = netbird_peer.bao.ip
  ttl     = 60

  lifecycle {
    prevent_destroy = true
  }
}

resource "netbird_dns_zone" "cpa" {
  name                 = "Private CPA"
  domain               = "cpa.vpn.denys.me"
  enabled              = true
  enable_search_domain = false
  distribution_groups  = [netbird_group.cpa_admins.id, netbird_group.cpa_server.id]

  lifecycle {
    prevent_destroy = true
  }
}

resource "netbird_dns_record" "cpa" {
  zone_id = netbird_dns_zone.cpa.id
  name    = "cpa.vpn.denys.me"
  type    = "A"
  content = netbird_peer.chunkymonkey.ip
  ttl     = 60

  lifecycle {
    prevent_destroy = true
  }
}
