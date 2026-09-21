module "state" {
  source = "./modules/terraform-state"
}

module "bao_support" {
  source = "./modules/bao-support"

  providers = {
    aws = aws.ca_central_1
  }
}

module "netbird_access" {
  source = "./modules/netbird-access"

  bao_dns_zone_name  = "Private OpenBao"
  bao_admin_peer_ids = ["dag13hqfadhs739d7rg0"]
  cpa_admin_peer_ids = ["dag13hqfadhs739d7rg0"]
}

module "railway_services" {
  source = "./modules/railway-services"
}
