moved {
  from = cloudflare_record.A-www
  to   = cloudflare_dns_record.A-www
}

moved {
  from = cloudflare_record.CNAME-www-wildcard
  to   = cloudflare_dns_record.CNAME-www-wildcard
}

moved {
  from = cloudflare_record.TXT-bsky
  to   = cloudflare_dns_record.TXT-bsky
}

moved {
  from = cloudflare_record.parked-A
  to   = cloudflare_dns_record.parked-A
}

moved {
  from = cloudflare_record.parked-www-CNAME
  to   = cloudflare_dns_record.parked-www-CNAME
}

moved {
  from = cloudflare_record.parked-wildcard-CNAME
  to   = cloudflare_dns_record.parked-wildcard-CNAME
}

moved {
  from = cloudflare_record.parked-MX1
  to   = cloudflare_dns_record.parked-MX1
}

moved {
  from = cloudflare_record.parked-MX2
  to   = cloudflare_dns_record.parked-MX2
}

moved {
  from = cloudflare_record.parked-SPF
  to   = cloudflare_dns_record.parked-SPF
}

moved {
  from = cloudflare_record.parked-DKIM1-CNAME
  to   = cloudflare_dns_record.parked-DKIM1-CNAME
}

moved {
  from = cloudflare_record.parked-DKIM2-CNAME
  to   = cloudflare_dns_record.parked-DKIM2-CNAME
}

moved {
  from = cloudflare_record.parked-DKIM3-CNAME
  to   = cloudflare_dns_record.parked-DKIM3-CNAME
}
