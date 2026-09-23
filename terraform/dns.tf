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

data "cloudflare_zone" "pvlv" {
  filter = {
    name = "pvlv.ca"
  }
}

resource "cloudflare_dns_record" "A-cli-proxy-api" {
  zone_id = data.cloudflare_zone.pvlv.id
  type    = "A"
  name    = "cpa"
  content = "192.18.149.148"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "TXT-vpn-private" {
  zone_id = cloudflare_zone.main.id
  type    = "TXT"
  name    = "*.vpn"
  content = "private-netbird-only"
  comment = "Prevent public wildcard address resolution under vpn.denys.me"
  proxied = false
  ttl     = 300
}

resource "cloudflare_ruleset" "pvlv_configuration" {
  zone_id = data.cloudflare_zone.pvlv.id
  name    = "pvlv.ca configuration"
  kind    = "zone"
  phase   = "http_config_settings"

  rules = [{
    ref         = "cpa_strict_tls"
    description = "Verify Traefik TLS for CLIProxyAPI"
    expression  = "http.host eq \"cpa.pvlv.ca\""
    action      = "set_config"
    enabled     = true
    action_parameters = {
      ssl = "strict"
    }
  }]
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

moved {
  from = cloudflare_dns_record.CNAME-paseo
  to   = cloudflare_dns_record.A-paseo
}

resource "cloudflare_dns_record" "A-paseo" {
  zone_id = cloudflare_zone.main.id
  type    = "A"
  name    = "paseo"
  content = "192.18.149.148"
  proxied = true
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

resource "cloudflare_dns_record" "amp-verification" {
  zone_id = data.cloudflare_zone.pvlv.id
  type    = "TXT"
  name    = "_amp-challenge.amp.pvlv.ca"
  content = "amp-domain-verification=d991575b865348a28111dd90daac29414464a9719485440b81048a88d2728ba1"
  comment = "Amp custom-domain ownership verification"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "amp-A" {
  zone_id = data.cloudflare_zone.pvlv.id
  type    = "A"
  name    = "amp.pvlv.ca"
  content = "34.49.94.208"
  comment = "Amp custom domain"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "amp-wildcard-A" {
  zone_id = data.cloudflare_zone.pvlv.id
  type    = "A"
  name    = "*.amp.pvlv.ca"
  content = "34.49.94.208"
  comment = "Amp custom-domain wildcard"
  proxied = false
  ttl     = 1
}

module "parked_domains" {
  source = "./modules/parked-domains"

  parked_domains = var.parked_domains
  ipv4_address   = digitalocean_droplet.www.ipv4_address
}
