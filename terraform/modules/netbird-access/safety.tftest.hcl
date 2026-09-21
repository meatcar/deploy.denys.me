mock_provider "netbird" {
  override_data {
    target = data.netbird_peers.bao
    values = { ids = ["bao-peer"] }
  }
  override_data {
    target = data.netbird_peers.chunkymonkey
    values = { ids = ["cpa-peer"] }
  }
  override_resource {
    target = netbird_peer.bao
    values = { ip = "10.201.219.143" }
  }
  override_resource {
    target = netbird_peer.chunkymonkey
    values = { ip = "10.201.92.223" }
  }
  override_resource {
    target = netbird_group.bao_admins
    values = { id = "bao-admins" }
  }
  override_resource {
    target = netbird_group.bao_server
    values = { id = "bao-server" }
  }
  override_resource {
    target = netbird_group.cpa_admins
    values = { id = "cpa-admins" }
  }
  override_resource {
    target = netbird_group.cpa_server
    values = { id = "cpa-server" }
  }
}

variables {
  bao_admin_peer_ids = ["bao-admin-laptop", "bao-admin-desktop"]
  cpa_admin_peer_ids = ["cpa-admin-laptop"]
}

run "management_access_and_dns_stay_separate" {
  command = plan

  assert {
    condition = alltrue([
      for name, policy in { bao = netbird_policy.bao, cpa = netbird_policy.cpa } :
      policy.enabled && length(policy.rule) == 1 &&
      alltrue([for rule in policy.rule :
        rule.enabled && rule.action == "accept" && rule.protocol == "tcp" && !rule.bidirectional &&
        toset(rule.ports) == toset(name == "bao" ? ["443"] : ["443", "9443"]) &&
        toset(rule.sources) == toset(["${name}-admins"]) &&
        toset(rule.destinations) == toset(["${name}-server"])
      ])
    ])
    error_message = "Management must allow only each service's administrators to its own server and HTTPS port."
  }

  assert {
    condition = (
      toset(netbird_group.bao_admins.peers) == toset(["bao-admin-laptop", "bao-admin-desktop"]) &&
      toset(netbird_group.cpa_admins.peers) == toset(["cpa-admin-laptop"]) &&
      toset(netbird_group.bao_server.peers) == toset(["bao-peer"]) &&
      toset(netbird_group.cpa_server.peers) == toset(["cpa-peer"])
    )
    error_message = "Administrator memberships must not be dropped or shared across services."
  }

  assert {
    condition = alltrue([
      for name, zone in { bao = netbird_dns_zone.bao, cpa = netbird_dns_zone.cpa } :
      zone.domain == "${name}.vpn.denys.me" && zone.enabled && !zone.enable_search_domain &&
      zone.distribution_groups == toset(["${name}-admins", "${name}-server"])
    ])
    error_message = "Private DNS zones must be hostname-specific and distributed only to the corresponding groups."
  }

  assert {
    condition = (
      netbird_dns_record.bao.name == "bao.vpn.denys.me" && netbird_dns_record.bao.content == "10.201.219.143" &&
      netbird_dns_record.cpa.name == "cpa.vpn.denys.me" && netbird_dns_record.cpa.content == "10.201.92.223"
    )
    error_message = "Each hostname must resolve to its own VPN server, not the other service or a public address."
  }
}
