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
    target = netbird_peer.private
    values = { ip = "10.201.0.20" }
  }
  override_data {
    target = data.netbird_group.all
    values = { id = "all" }
  }
  override_resource {
    target = netbird_group.role_admins
    values = { id = "role-admins" }
  }
  override_resource {
    target = netbird_group.role_agent_vms
    values = { id = "role-agent-vms" }
  }
  override_resource {
    target = netbird_group.server_bao
    values = { id = "server-bao" }
  }
  override_resource {
    target = netbird_group.server_chunkymonkey
    values = { id = "server-chunkymonkey" }
  }
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
        toset(rule.sources) == toset(["role-admins"]) &&
        toset(rule.destinations) == toset([name == "bao" ? "server-bao" : "server-chunkymonkey"])
      ])
    ])
    error_message = "Management must allow only administrators to each service's own server and HTTPS port."
  }

  assert {
    condition = (
      toset(netbird_group.server_bao.peers) == toset(["bao-peer"]) &&
      toset(netbird_group.server_chunkymonkey.peers) == toset(["cpa-peer"])
    )
    error_message = "Each server group must contain only its own pinned peer."
  }

  assert {
    condition = alltrue([
      for name, zone in { bao = netbird_dns_zone.bao, cpa = netbird_dns_zone.cpa } :
      zone.domain == "${name}.vpn.denys.me" && zone.enabled && !zone.enable_search_domain &&
      zone.distribution_groups == toset(name == "bao"
        ? ["role-admins", "server-bao", "role-agent-vms"]
      : ["role-admins", "server-chunkymonkey"])
    ])
    error_message = "Private DNS zones must be hostname-specific; agent VMs receive only Bao DNS, not CPA DNS."
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
      for name in ["billing", "trmnl", "txt"] :
      netbird_dns_zone.apps[name].domain == "${name}.vpn.denys.me" &&
      netbird_dns_zone.apps[name].distribution_groups == toset(["role-admins", "server-chunkymonkey"]) &&
      netbird_dns_record.apps[name].content == "10.201.92.223"
    ])
    error_message = "Billing, TRMNL and SilverBullet administration must use Chunkymonkey's administrator-only 443/9443 entrypoint, not Bao or public DNS."
  }
}

run "unenrolled_servers_are_not_granted_access" {
  command = plan

  assert {
    condition = (
      length(data.netbird_peer.private) == 0 &&
      length(netbird_group.server) == 0 &&
      length(netbird_policy.private) == 0 &&
      length(netbird_dns_zone.private) == 0
    )
    error_message = "Without an explicit enrolled VPS address, no lookup, destination, policy or private DNS may be created."
  }
}

run "enrolled_servers_get_only_declared_access" {
  command = plan
  variables {
    private_server_ips = { vps = "10.201.0.20" }
  }

  assert {
    condition = (
      netbird_group.role_agent_vms.name == "role-agent-vms" &&
      netbird_policy.agent_vms_bao.enabled && length(netbird_policy.agent_vms_bao.rule) == 1 &&
      alltrue([for rule in netbird_policy.agent_vms_bao.rule :
        rule.enabled && rule.action == "accept" && !rule.bidirectional && rule.protocol == "tcp" &&
        toset(rule.sources) == toset(["role-agent-vms"]) &&
        toset(rule.destinations) == toset(["server-bao"]) &&
        toset(rule.ports) == toset(["443"]) && length(coalesce(rule.port_ranges, [])) == 0
      ])
    )
    error_message = "Agent VMs must have exactly one one-way TCP/443 grant to Bao only, without port ranges."
  }
  assert {
    condition = alltrue([
      for policy in concat([netbird_policy.bao, netbird_policy.cpa], values(netbird_policy.private)) :
      alltrue([for rule in policy.rule :
        !contains(rule.sources, "role-agent-vms") && !contains(rule.destinations, "role-agent-vms")
      ])
    ])
    error_message = "Agent VMs must not participate in administrator, CPA or VPS policies in either direction."
  }
  assert {
    condition = alltrue([
      for zone in concat([netbird_dns_zone.cpa], values(netbird_dns_zone.apps), values(netbird_dns_zone.private)) :
      !contains(zone.distribution_groups, "role-agent-vms")
    ])
    error_message = "Agent VMs must not receive CPA, application or VPS DNS zones."
  }

  assert {
    condition = (
      toset(netbird_group.server["vps"].peers) == toset([netbird_peer.private["vps"].id]) &&
      toset(keys(netbird_policy.private)) == toset(["vps-web", "vps-irc", "vps-ssh", "vps-mosh"])
    )
    error_message = "Each destination must contain only its verified peer; no full-mesh or extra service policies are allowed."
  }
  assert {
    condition = alltrue([
      for name, expected in {
        vps-web = { destination = "vps", ports = ["443", "9443"] }
        vps-irc = { destination = "vps", ports = ["7000"] }
        vps-ssh = { destination = "vps", ports = ["22"] }
        } : alltrue([for rule in netbird_policy.private[name].rule :
          rule.enabled && rule.action == "accept" && !rule.bidirectional && rule.protocol == "tcp" &&
          toset(rule.sources) == toset(["role-admins"]) &&
          toset(rule.destinations) == toset([netbird_group.server[expected.destination].id]) &&
          toset(rule.ports) == toset(expected.ports) && length(coalesce(rule.port_ranges, [])) == 0
      ])
    ])
    error_message = "HTTP, IRC and SSH must have exact directional sources, destinations and ports."
  }
  assert {
    condition = alltrue([for host in ["vps"] : alltrue([
      for rule in netbird_policy.private["${host}-mosh"].rule :
      rule.enabled && rule.action == "accept" && !rule.bidirectional && rule.protocol == "udp" &&
      toset(rule.sources) == toset(["role-admins"]) &&
      toset(rule.destinations) == toset([netbird_group.server[host].id]) &&
      length(coalesce(rule.ports, [])) == 0 && length(rule.port_ranges) == 1 &&
      rule.port_ranges[0].start == 60000 && rule.port_ranges[0].end == 61000
    ])])
    error_message = "Mosh must be administrator-only UDP/60000-61000, never all UDP or bidirectional."
  }
  assert {
    condition     = netbird_dns_record.private["znc.denys.me"].content == "10.201.0.20"
    error_message = "Split DNS must target the enrolled VPS."
  }
}

run "account_defaults_stay_closed" {
  command = plan

  assert {
    condition = (
      !netbird_policy.default.enabled &&
      netbird_account_settings.this.groups_propagation_enabled &&
      netbird_account_settings.this.network_range == "10.201.0.0/16" &&
      netbird_account_settings.this.user_approval_required &&
      netbird_setup_key.agent_vms.ephemeral && !netbird_setup_key.agent_vms.allow_extra_dns_labels &&
      netbird_setup_key.agent_vms.auto_groups == tolist(["role-agent-vms"]) &&
      netbird_user.owner.auto_groups == tolist(["role-admins"]) && length(netbird_user.terraform.auto_groups) == 0
    )
    error_message = "Default allow-all stays off; only declared users join role-admins; the agent VM key joins only role-agent-vms; pinned peer IPs keep their range."
  }
}
