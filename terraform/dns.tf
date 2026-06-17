resource "cloudflare_zone" "main" {
  name = var.cloudflare_domain
  account = {
    id = var.cloudflare_account_id
  }
}

resource "cloudflare_dns_record" "A-www" {
  zone_id = cloudflare_zone.main.id
  type    = "A"
  name    = var.hostname
  content = digitalocean_droplet.www.ipv4_address
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "CNAME-www-wildcard" {
  zone_id = cloudflare_zone.main.id
  type    = "CNAME"
  name    = "*.${cloudflare_dns_record.A-www.name}"
  content = cloudflare_dns_record.A-www.name
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "TXT-bsky" {
  zone_id = cloudflare_zone.main.id
  type    = "TXT"
  name    = "_atproto."
  content = "did=did:plc:t4ilp6pghizmrfhgsiw65md4"
  comment = "for bluesky.social"
  proxied = false
  ttl     = 1
}

## Parked Domains

data "cloudflare_zone" "parked" {
  for_each = toset(var.parked_domains)

  filter = {
    name = each.key
  }
}

resource "cloudflare_dns_record" "parked-A" {
  for_each = toset(var.parked_domains)

  zone_id = data.cloudflare_zone.parked[each.key].id
  type    = "A"
  name    = each.key
  content = digitalocean_droplet.www.ipv4_address
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "parked-www-CNAME" {
  for_each = toset(var.parked_domains)

  zone_id = data.cloudflare_zone.parked[each.key].id
  type    = "CNAME"
  name    = "www.${each.key}"
  content = each.key
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "parked-wildcard-CNAME" {
  for_each = toset(var.parked_domains)

  zone_id = data.cloudflare_zone.parked[each.key].id
  type    = "CNAME"
  name    = "*.${each.key}"
  content = each.key
  ttl     = 1
}

resource "cloudflare_dns_record" "parked-MX1" {
  for_each = toset(var.parked_domains)

  zone_id  = data.cloudflare_zone.parked[each.key].id
  type     = "MX"
  name     = "@"
  content  = "in1-smtp.messagingengine.com"
  priority = 10
  ttl      = 1
}

resource "cloudflare_dns_record" "parked-MX2" {
  for_each = toset(var.parked_domains)

  zone_id  = data.cloudflare_zone.parked[each.key].id
  type     = "MX"
  name     = "@"
  content  = "in2-smtp.messagingengine.com"
  priority = 20
  ttl      = 1
}

resource "cloudflare_dns_record" "parked-SPF" {
  for_each = toset(var.parked_domains)

  zone_id = data.cloudflare_zone.parked[each.key].id
  type    = "TXT"
  name    = "@"
  content = "v=spf1 include:spf.messagingengine.com ?all"
  ttl     = 1
}

resource "cloudflare_dns_record" "parked-DKIM1-CNAME" {
  for_each = toset(var.parked_domains)

  zone_id = data.cloudflare_zone.parked[each.key].id
  type    = "CNAME"
  name    = "fm1._domainkey"
  content = "fm1.${each.key}.dkim.fmhosted.com"
  ttl     = 1
}

resource "cloudflare_dns_record" "parked-DKIM2-CNAME" {
  for_each = toset(var.parked_domains)

  zone_id = data.cloudflare_zone.parked[each.key].id
  type    = "CNAME"
  name    = "fm2._domainkey"
  content = "fm2.${each.key}.dkim.fmhosted.com"
  ttl     = 1
}

resource "cloudflare_dns_record" "parked-DKIM3-CNAME" {
  for_each = toset(var.parked_domains)

  zone_id = data.cloudflare_zone.parked[each.key].id
  type    = "CNAME"
  name    = "fm3._domainkey"
  content = "fm3.${each.key}.dkim.fmhosted.com"
  ttl     = 1
}
