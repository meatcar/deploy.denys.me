# for state
provider "aws" {
  region  = "us-east-1"
}

provider "cloudflare" {
  email     = var.cloudflare_email
  api_token = var.cloudflare_token
}

provider "digitalocean" {
  token   = var.digitalocean_token
}

module "state" {
  source = "./tf-modules/terraform-state"
}
