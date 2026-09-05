terraform {
  required_version = ">= 1.11.0"

  backend "s3" {
    bucket       = "terraform-state-denys-me"
    key          = "railway/state"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    railway = {
      source  = "terraform-community-providers/railway"
      version = "= 0.6.2"
    }
  }
}

provider "railway" {}
