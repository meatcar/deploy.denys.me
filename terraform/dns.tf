resource "cloudflare_zone" "main" {
  zone = var.cloudflare_domain
}

resource "cloudflare_record" "A-www" {
  zone_id = cloudflare_zone.main.id
  type    = "A"
  name    = var.hostname
  value   = digitalocean_droplet.www.ipv4_address
  proxied = true
}

resource "cloudflare_record" "CNAME-www-wildcard" {
  zone_id = cloudflare_zone.main.id
  type    = "CNAME"
  name    = "*.${cloudflare_record.A-www.name}"
  value   = cloudflare_record.A-www.name
  proxied = false
}

## Parked Domains

resource "cloudflare_zone" "parked" {
  for_each = toset( var.parked_domains )

  zone = each.key
}

resource "cloudflare_record" "parked-A" {
  for_each = toset( var.parked_domains )

  zone_id = cloudflare_zone.parked[each.key].id
  type = "A"
  name = each.key
  value = digitalocean_droplet.www.ipv4_address
  proxied = true
}

resource "cloudflare_record" "parked-www-CNAME" {
  for_each = toset( var.parked_domains )

  zone_id = cloudflare_zone.parked[each.key].id
  type = "CNAME"
  name = "www.${each.key}"
  value = each.key
  proxied = true
}

resource "cloudflare_record" "parked-wildcard-CNAME" {
  for_each = toset( var.parked_domains )

  zone_id = cloudflare_zone.parked[each.key].id
  type = "CNAME"
  name = "*.${each.key}"
  value = each.key
}

resource "cloudflare_record" "parked-MX1" {
  for_each = toset( var.parked_domains )

  zone_id = cloudflare_zone.parked[each.key].id
  type = "MX"
  name = "@"
  value = "in1-smtp.messagingengine.com"
  priority = 10
}

resource "cloudflare_record" "parked-MX2" {
  for_each = toset( var.parked_domains )

  zone_id = cloudflare_zone.parked[each.key].id
  type = "MX"
  name = "@"
  value = "in2-smtp.messagingengine.com"
  priority = 20
}

resource "cloudflare_record" "parked-SPF" {
  for_each = toset( var.parked_domains )

  zone_id = cloudflare_zone.parked[each.key].id
  type = "TXT"
  name = "@"
  value = "v=spf1 include:spf.messagingengine.com ?all"
}

resource "cloudflare_record" "parked-DKIM1-CNAME" {
  for_each = toset( var.parked_domains )

  zone_id = cloudflare_zone.parked[each.key].id
  type = "CNAME"
  name = "fm1._domainkey"
  value = "fm1.${each.key}.dkim.fmhosted.com"
}

resource "cloudflare_record" "parked-DKIM2-CNAME" {
  for_each = toset( var.parked_domains )

  zone_id = cloudflare_zone.parked[each.key].id
  type = "CNAME"
  name = "fm2._domainkey"
  value = "fm2.${each.key}.dkim.fmhosted.com"
}

resource "cloudflare_record" "parked-DKIM3-CNAME" {
  for_each = toset( var.parked_domains )

  zone_id = cloudflare_zone.parked[each.key].id
  type = "CNAME"
  name = "fm3._domainkey"
  value = "fm3.${each.key}.dkim.fmhosted.com"
}

resource "cloudflare_record" "parked-DMARC" {
  # some parked domains have a custom dmarc set.
  for_each = setsubtract(var.parked_domains, ["huddle.win"])
  zone_id = cloudflare_zone.parked[each.key].id
  type = "TXT"
  name = "_dmarc"
  value = "v=DMARC1;p=reject;sp=reject;adkim=s;aspf=s;fo=1;rua=mailto:dmarc@${each.key}"
}

resource "cloudflare_record" "huddle-win-DMARC" {
  zone_id = cloudflare_zone.parked["huddle.win"].id
  type = "TXT"
  name = "_dmarc"
  value = "v=DMARC1; p=none; pct=100; rua=mailto:re+olvgs5ajiab@dmarc.postmarkapp.com; sp=none; aspf=r;"

}
