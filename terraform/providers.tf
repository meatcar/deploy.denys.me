provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "ca_central_1"
  region = "ca-central-1"
}

provider "cloudflare" {
  api_token = var.cloudflare_token
}

provider "digitalocean" {
  token = var.digitalocean_token
}

provider "oci" {
  auth                = "SecurityToken"
  config_file_profile = var.oci_config_file_profile
  region              = var.oci_region
}

provider "ovh" {
  endpoint = "ovh-ca"
}

provider "netbird" {
  management_url = "https://api.netbird.io"
}

provider "railway" {}
