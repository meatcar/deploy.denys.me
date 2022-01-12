# for state
provider "aws" {
  version = "~> 3.56.0"
  region  = "us-east-1"
}

provider "cloudflare" {
  version   = "~> 2.23.0"
  email     = var.cloudflare_email
  api_token = var.cloudflare_token
}

provider "digitalocean" {
  version = "~> 2.2.0"
  token   = var.digitalocean_token
}

module "state" {
  source = "./tf-modules/terraform-state"
}
