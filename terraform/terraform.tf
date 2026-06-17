terraform {
  backend "s3" {
    bucket       = "terraform-state-denys-me"
    key          = "state"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.50"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.20"
    }
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.89"
    }
    oci = {
      source  = "oracle/oci"
      version = "~> 8.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.4"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.3"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
  required_version = ">= 1.8.0"
}
