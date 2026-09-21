include "root" {
  path = find_in_parent_folders("root.hcl")
}

inputs = {
  bao_dns_zone_id    = "dagddb2fadhs7386fqh0"
  bao_dns_record_id  = "dagddbbl0ubs73ahrt60"
  bao_policy_id      = "dafibfqfadhs739elrog"
  bao_dns_zone_name  = "Private OpenBao"
  bao_admin_peer_ids = ["dag13hqfadhs739d7rg0"]
  cpa_admin_peer_ids = ["dag13hqfadhs739d7rg0"]
}
