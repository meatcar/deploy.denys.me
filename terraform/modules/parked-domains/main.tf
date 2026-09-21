data "cloudflare_zone" "parked" {
  for_each = var.parked_domains

  filter = {
    name = each.key
  }
}

resource "cloudflare_dns_record" "parked-A" {
  for_each = var.parked_domains

  zone_id = data.cloudflare_zone.parked[each.key].id
  type    = "A"
  name    = each.key
  content = var.ipv4_address
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "parked-www-CNAME" {
  for_each = var.parked_domains

  zone_id = data.cloudflare_zone.parked[each.key].id
  type    = "CNAME"
  name    = "www.${each.key}"
  content = each.key
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "parked-wildcard-CNAME" {
  for_each = var.parked_domains

  zone_id = data.cloudflare_zone.parked[each.key].id
  type    = "CNAME"
  name    = "*.${each.key}"
  content = each.key
  ttl     = 1
}

resource "cloudflare_dns_record" "parked-MX1" {
  for_each = var.parked_domains

  zone_id  = data.cloudflare_zone.parked[each.key].id
  type     = "MX"
  name     = "@"
  content  = "in1-smtp.messagingengine.com"
  priority = 10
  ttl      = 1
}

resource "cloudflare_dns_record" "parked-MX2" {
  for_each = var.parked_domains

  zone_id  = data.cloudflare_zone.parked[each.key].id
  type     = "MX"
  name     = "@"
  content  = "in2-smtp.messagingengine.com"
  priority = 20
  ttl      = 1
}

resource "cloudflare_dns_record" "parked-SPF" {
  for_each = var.parked_domains

  zone_id = data.cloudflare_zone.parked[each.key].id
  type    = "TXT"
  name    = "@"
  content = "v=spf1 include:spf.messagingengine.com ?all"
  ttl     = 1
}

resource "cloudflare_dns_record" "parked-DKIM1-CNAME" {
  for_each = var.parked_domains

  zone_id = data.cloudflare_zone.parked[each.key].id
  type    = "CNAME"
  name    = "fm1._domainkey"
  content = "fm1.${each.key}.dkim.fmhosted.com"
  ttl     = 1
}

resource "cloudflare_dns_record" "parked-DKIM2-CNAME" {
  for_each = var.parked_domains

  zone_id = data.cloudflare_zone.parked[each.key].id
  type    = "CNAME"
  name    = "fm2._domainkey"
  content = "fm2.${each.key}.dkim.fmhosted.com"
  ttl     = 1
}

resource "cloudflare_dns_record" "parked-DKIM3-CNAME" {
  for_each = var.parked_domains

  zone_id = data.cloudflare_zone.parked[each.key].id
  type    = "CNAME"
  name    = "fm3._domainkey"
  content = "fm3.${each.key}.dkim.fmhosted.com"
  ttl     = 1
}
