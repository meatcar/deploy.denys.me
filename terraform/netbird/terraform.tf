terraform {
  required_version = ">= 1.11.0"

  backend "s3" {
    bucket       = "terraform-state-denys-me"
    key          = "netbird/state"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    netbird = {
      source  = "netbirdio/netbird"
      version = "= 0.0.10"
    }
  }
}

provider "netbird" {
  management_url = "https://api.netbird.io"
}
