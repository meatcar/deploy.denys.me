locals {
  nix_cache = jsondecode(file(abspath("${var.repository_root}/nixos/systems/chunkymonkey/niks3.json")))
}

resource "cloudflare_r2_bucket" "nix_cache" {
  account_id = var.cloudflare_account_id
  name       = local.nix_cache.bucket
  location   = "enam"
}

resource "cloudflare_dns_record" "A-cache" {
  zone_id = cloudflare_zone.main.id
  type    = "A"
  name    = trimsuffix(local.nix_cache.host, ".${cloudflare_zone.main.name}")
  content = "192.18.149.148"
  proxied = true
  ttl     = 1
}
