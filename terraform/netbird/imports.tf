import {
  to = netbird_peer.bao
  id = one(data.netbird_peers.bao.ids)
}

import {
  to = netbird_peer.chunkymonkey
  id = one(data.netbird_peers.chunkymonkey.ids)
}

import {
  to = netbird_group.bao_admins
  id = data.netbird_group.bao_admins.id
}

import {
  to = netbird_group.bao_server
  id = data.netbird_group.bao_server.id
}

import {
  to = netbird_policy.bao
  id = var.bao_policy_id
}

import {
  to = netbird_dns_zone.bao
  id = var.bao_dns_zone_id
}

import {
  to = netbird_dns_record.bao
  id = "${var.bao_dns_zone_id}:${var.bao_dns_record_id}"
}
