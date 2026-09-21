mock_provider "cloudflare" {}

variables {
  parked_domains = ["first.example", "second.test"]
  ipv4_address   = "203.0.113.27"
}

run "parking_preserves_web_and_mail" {
  command = plan

  assert {
    condition = {
      for domain, record in cloudflare_dns_record.parked-A : domain => record.content
      } == {
      "first.example" = "203.0.113.27"
      "second.test"   = "203.0.113.27"
    }
    error_message = "Each parked domain must route to the supplied host."
  }

  assert {
    condition = (
      cloudflare_dns_record.parked-www-CNAME["first.example"].name == "www.first.example" &&
      cloudflare_dns_record.parked-wildcard-CNAME["second.test"].name == "*.second.test" &&
      cloudflare_dns_record.parked-wildcard-CNAME["second.test"].content == "second.test" &&
      cloudflare_dns_record.parked-DKIM3-CNAME["second.test"].content == "fm3.second.test.dkim.fmhosted.com"
    )
    error_message = "Aliases and DKIM must use their own domain, not another domain in the set."
  }

  assert {
    condition = (
      cloudflare_dns_record.parked-MX1["first.example"].priority == 10 &&
      cloudflare_dns_record.parked-MX1["first.example"].content == "in1-smtp.messagingengine.com" &&
      cloudflare_dns_record.parked-MX2["first.example"].priority == 20 &&
      cloudflare_dns_record.parked-MX2["first.example"].content == "in2-smtp.messagingengine.com" &&
      cloudflare_dns_record.parked-SPF["first.example"].content == "v=spf1 include:spf.messagingengine.com ?all"
    )
    error_message = "Parking must preserve Fastmail delivery priorities and SPF."
  }
}
