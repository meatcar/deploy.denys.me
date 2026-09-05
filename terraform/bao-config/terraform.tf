terraform {
  required_version = ">= 1.11.0"

  backend "s3" {
    bucket       = "terraform-state-denys-me"
    key          = "bao-config/state"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "= 5.12.0"
    }
  }
}

provider "vault" {
  address          = "https://bao.vpn.denys.me"
  skip_child_token = !var.use_aws_auth

  dynamic "auth_login_aws" {
    for_each = var.use_aws_auth ? [true] : []
    content {
      mount        = "aws"
      role         = "terraform-admin"
      aws_region   = "ca-central-1"
      header_value = "bao.vpn.denys.me"
    }
  }
}
