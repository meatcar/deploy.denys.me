mock_provider "aws" {}
mock_provider "aws" {
  alias = "ca_central_1"

  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  override_data {
    target = module.bao_support.data.aws_caller_identity.current
    values = { account_id = "123456789012" }
  }
}
mock_provider "cloudflare" {
  mock_data "cloudflare_zone" {
    defaults = { id = "0123456789abcdef0123456789abcdef" }
  }
}
mock_provider "digitalocean" {}
mock_provider "oci" {}
mock_provider "ovh" {}
mock_provider "netbird" {
  override_data {
    target = module.netbird_access.data.netbird_peers.bao
    values = { ids = ["bao-peer"] }
  }
  override_data {
    target = module.netbird_access.data.netbird_peers.chunkymonkey
    values = { ids = ["cpa-peer"] }
  }
}
mock_provider "railway" {}
mock_provider "external" {
  mock_data "external" {
    defaults = {
      result = { public_key = "test-public-key", private_key = "test-private-key" }
    }
  }
}
mock_provider "local" {}
mock_provider "random" {}
mock_provider "null" {}

override_module {
  # NOTE: OpenTofu 1.11 cannot mock Railway's nested environment ID; storage is tested in the module.
  target = module.railway_services
}

variables {
  ssh_fingerprint       = "test-fingerprint"
  digitalocean_token    = "test-token"
  cloudflare_token      = "test-token"
  cloudflare_account_id = "0123456789abcdef0123456789abcdef"
  cloudflare_domain     = "example.test"
  parked_domains        = []
  hostname              = "www.example.test"
  oci_region            = "ca-toronto-1"
  oci_compartment_ocid  = "ocid1.compartment.oc1..test"
}

override_resource {
  target = digitalocean_droplet.www
  values = {
    ipv4_address = "203.0.113.17"
  }
}

run "host_and_backend_contracts" {
  command = plan

  assert {
    condition     = output.ip == "203.0.113.17" && output.fqdn == "www.example.test"
    error_message = "Consolidation must preserve the main root's host outputs."
  }

  assert {
    condition     = length(ovh_vps.bao.plan) == 0
    error_message = "The adopted Bao VPS must not acquire a purchase/reinstall plan."
  }

  assert {
    condition = (
      output.openbao_iam_user == "openbao-vpn-runtime" &&
      output.backup_bucket == "openbao-vpn-backup-123456789012" &&
      output.backup_iam_user == "openbao-vpn-backup"
    )
    error_message = "The infrastructure root must preserve Bao's output contract."
  }

  assert {
    condition = (
      cloudflare_dns_record.A-www.content == "203.0.113.17" &&
      cloudflare_dns_record.A-billing.proxied &&
      !cloudflare_dns_record.A-billing-sns.proxied &&
      cloudflare_dns_record.TXT-vpn-private.content == "private-netbird-only"
    )
    error_message = "Composition must preserve host routing, the direct SNS endpoint, and the private VPN wildcard guard."
  }
}
