moved {
  from = netbird_group.deploy_orbs
  to   = netbird_group.role_agent_vms
}

moved {
  from = netbird_policy.deploy_orbs_bao
  to   = netbird_policy.agent_vms_bao
}

moved {
  from = netbird_group.bao_server
  to   = netbird_group.server_bao
}

moved {
  from = netbird_group.cpa_server
  to   = netbird_group.server_chunkymonkey
}

moved {
  from = netbird_group.private_server
  to   = netbird_group.server
}
