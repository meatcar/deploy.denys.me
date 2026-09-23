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

run "private_application_dns_uses_existing_management_boundary" {
  command = plan

  assert {
    condition = alltrue([
      for name in ["billing", "trmnl"] :
      netbird_dns_zone.apps[name].domain == "${name}.vpn.denys.me" &&
      netbird_dns_zone.apps[name].distribution_groups == toset(["cpa-admins", "cpa-server"]) &&
      netbird_dns_record.apps[name].content == "10.201.92.223"
    ])
    error_message = "Billing and TRMNL must use Chunkymonkey's administrator-only 443/9443 entrypoint, not Bao or public DNS."
  }
}

run "unenrolled_servers_are_not_granted_access" {
  command = plan

  assert {
    condition = (
      length(data.netbird_peer.private) == 0 &&
      length(netbird_group.private_server) == 0 &&
      length(netbird_policy.private) == 0 &&
      length(netbird_dns_zone.private) == 0
    )
    error_message = "Without explicit enrolled Cube/VPS addresses, no lookup, destination, policy or private DNS may be created."
  }
}

run "enrolled_servers_get_only_declared_access" {
  command = plan
  variables {
    private_server_ips = { cube = "10.201.0.10", vps = "10.201.0.20" }
    private_access_peer_ids = {
      administrators = ["administrator-fixture"]
      household      = ["household-fixture"]
      storage        = ["storage-fixture"]
    }
  }

  assert {
    condition = alltrue([
      for role, peers in {
        administrators = ["administrator-fixture"], household = ["household-fixture"], storage = ["storage-fixture"]
      } : toset(netbird_group.access[role].peers) == toset(peers)
    ])
    error_message = "The three roles must have independent, complete, explicitly supplied memberships."
  }
  assert {
    condition = (
      toset(netbird_group.private_server["cube"].peers) == toset([data.netbird_peer.private["cube"].id]) &&
      toset(netbird_group.private_server["vps"].peers) == toset([data.netbird_peer.private["vps"].id]) &&
      toset(keys(netbird_policy.private)) == toset(["cube-web", "cube-storage", "vps-web", "vps-irc", "cube-ssh", "cube-mosh", "vps-ssh", "vps-mosh"])
    )
    error_message = "Each destination must contain only its verified peer; no full-mesh or extra service policies are allowed."
  }
  assert {
    condition = alltrue([
      for name, expected in {
        cube-web     = { sources = ["administrators", "household"], destination = "cube", ports = ["443", "9443"] }
        cube-storage = { sources = ["storage"], destination = "cube", ports = ["445"] }
        vps-web      = { sources = ["administrators"], destination = "vps", ports = ["443", "9443"] }
        vps-irc      = { sources = ["administrators"], destination = "vps", ports = ["7000"] }
        cube-ssh     = { sources = ["administrators"], destination = "cube", ports = ["22"] }
        vps-ssh      = { sources = ["administrators"], destination = "vps", ports = ["22"] }
        } : alltrue([for rule in netbird_policy.private[name].rule :
          rule.enabled && rule.action == "accept" && !rule.bidirectional && rule.protocol == "tcp" &&
          toset(rule.sources) == toset([for role in expected.sources : netbird_group.access[role].id]) &&
          toset(rule.destinations) == toset([netbird_group.private_server[expected.destination].id]) &&
          toset(rule.ports) == toset(expected.ports) && length(coalesce(rule.port_ranges, [])) == 0
      ])
    ])
    error_message = "HTTP, SMB, IRC and SSH must have exact directional sources, destinations and ports."
  }
  assert {
    condition = alltrue([for host in ["cube", "vps"] : alltrue([
      for rule in netbird_policy.private["${host}-mosh"].rule :
      rule.enabled && rule.action == "accept" && !rule.bidirectional && rule.protocol == "udp" &&
      toset(rule.sources) == toset([netbird_group.access["administrators"].id]) &&
      toset(rule.destinations) == toset([netbird_group.private_server[host].id]) &&
      length(coalesce(rule.ports, [])) == 0 && length(rule.port_ranges) == 1 &&
      rule.port_ranges[0].start == 60000 && rule.port_ranges[0].end == 61000
    ])])
    error_message = "Mosh must be administrator-only UDP/60000-61000, never all UDP or bidirectional."
  }
  assert {
    condition = (
      netbird_dns_record.private["sonarr.cube.denys.me"].content == "10.201.0.10" &&
      netbird_dns_record.private["znc.denys.me"].content == "10.201.0.20" &&
      alltrue([for record in netbird_dns_record.public_cube : record.type == "CNAME" && record.content == "denys.me"])
    )
    error_message = "Split DNS must target enrolled private servers while preserving public Plex/Ombi routing."
  }
}
