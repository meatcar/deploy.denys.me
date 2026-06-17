# for state
provider "aws" {
  region = "us-east-1"
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

module "state" {
  source = "./tf-modules/terraform-state"
}
