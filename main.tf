# for state
provider "aws" {
  version = "~> 2.8"
  region  = "us-east-1"
}

provider "cloudflare" {
  version   = "~> 2.1"
  email     = var.cloudflare_email
  api_token = var.cloudflare_token
}

provider "digitalocean" {
  version = "~> 1.11"
  token   = var.digitalocean_token
}

module "state" {
  source = "./tf-modules/terraform-state"
}
