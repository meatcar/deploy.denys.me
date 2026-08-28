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

resource "cloudflare_dns_record" "A-trmnl" {
  zone_id = cloudflare_zone.main.id
  type    = "A"
  name    = "trmnl"
  content = "192.18.149.148"
  proxied = true
  ttl     = 1
}

# Both services on chunkymonkey are proxied. The host firewall admits only
# Cloudflare source ranges to the shared origin ports, so the known origin IP
# cannot bypass edge policy. Certificates use Cloudflare DNS-01.
resource "cloudflare_dns_record" "A-billing" {
  zone_id = cloudflare_zone.main.id
  type    = "A"
  name    = "billing"
  content = "192.18.149.148"
  proxied = true
  ttl     = 1
}

# SNS delivery through Cloudflare is unreliable for signed notification bodies.
# This direct hostname exposes only the exact webhook route, while the host
# firewall admits AWS's non-EC2 ca-central-1 service prefix and rejects everyone
# else. The application still verifies each SNS signature and TopicArn.
resource "cloudflare_dns_record" "A-billing-sns" {
  zone_id = cloudflare_zone.main.id
  type    = "A"
  name    = "billing-sns"
  content = "192.18.149.148"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "CNAME-paseo" {
  zone_id = cloudflare_zone.main.id
  type    = "CNAME"
  name    = "paseo"
  content = "wymejaba.up.railway.app"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "TXT-paseo-railway" {
  zone_id = cloudflare_zone.main.id
  type    = "TXT"
  name    = "_railway-verify.paseo"
  content = "railway-verify=a89c4085ab056bede47b680daac316759884854b1763ab6c5c9ad23d7d95a5bd"
  comment = "Railway custom-domain ownership verification"
  proxied = false
  ttl     = 1
}

## Amazon SES (ca-central-1) - outbound mail for Invoice Ninja
#
# Explicit records are required here because the CNAME-www-wildcard record above
# otherwise answers for every unclaimed name under the zone, which would shadow
# both the DKIM lookups and the custom MAIL FROM domain.
#
# The domain identity, Easy DKIM, custom MAIL FROM, and SES production access
# are active in ca-central-1.

# Easy DKIM: SES publishes the signing keys, we just point at them.
resource "cloudflare_dns_record" "ses-dkim" {
  for_each = toset([
    "hjyo62rwk7fb2ywit2qaganbbcnk72pt",
    "ftur4fvj43xm7fksgbdin4gnephaiwil",
    "ecwfutngstrlhv7t2537gx5k2vj2mqjp",
  ])

  zone_id = cloudflare_zone.main.id
  type    = "CNAME"
  name    = "${each.key}._domainkey"
  content = "${each.key}.dkim.amazonses.com"
  comment = "Amazon SES Easy DKIM"
  proxied = false
  ttl     = 1
}

# Custom MAIL FROM domain, so the envelope sender aligns with denys.me for SPF
# rather than falling back to amazonses.com.
resource "cloudflare_dns_record" "ses-mail-from-MX" {
  zone_id  = cloudflare_zone.main.id
  type     = "MX"
  name     = "mail"
  content  = "feedback-smtp.ca-central-1.amazonses.com"
  priority = 10
  comment  = "Amazon SES custom MAIL FROM (bounce/complaint feedback)"
  ttl      = 1
}

resource "cloudflare_dns_record" "ses-mail-from-SPF" {
  zone_id = cloudflare_zone.main.id
  type    = "TXT"
  name    = "mail"
  content = "v=spf1 include:amazonses.com -all"
  comment = "Amazon SES custom MAIL FROM SPF"
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

## Amp custom domain

resource "cloudflare_dns_record" "amp-verification" {
  zone_id = data.cloudflare_zone.parked["pvlv.ca"].id
  type    = "TXT"
  name    = "_amp-challenge.amp.pvlv.ca"
  content = "amp-domain-verification=d991575b865348a28111dd90daac29414464a9719485440b81048a88d2728ba1"
  comment = "Amp custom-domain ownership verification"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "amp-A" {
  zone_id = data.cloudflare_zone.parked["pvlv.ca"].id
  type    = "A"
  name    = "amp.pvlv.ca"
  content = "34.49.94.208"
  comment = "Amp custom domain"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "amp-wildcard-A" {
  zone_id = data.cloudflare_zone.parked["pvlv.ca"].id
  type    = "A"
  name    = "*.amp.pvlv.ca"
  content = "34.49.94.208"
  comment = "Amp custom-domain wildcard"
  proxied = false
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
