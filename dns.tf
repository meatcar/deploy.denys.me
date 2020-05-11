resource "cloudflare_record" "A-www" {
  zone_id = var.cloudflare_zone_id
  type    = "A"
  name    = var.hostname
  value   = digitalocean_droplet.www.ipv4_address
  proxied = true
}

resource "cloudflare_record" "CNAME-www-wildcard" {
  zone_id = var.cloudflare_zone_id
  type    = "CNAME"
  name    = "*.${cloudflare_record.A-www.name}"
  value   = cloudflare_record.A-www.name
  proxied = false
}
