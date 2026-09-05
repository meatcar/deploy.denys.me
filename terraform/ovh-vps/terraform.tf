terraform {
  required_version = ">= 1.11.0"

  backend "s3" {
    bucket       = "terraform-state-denys-me"
    key          = "ovh-vps/state"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "= 2.19.0"
    }
  }
}

provider "ovh" {
  endpoint = "ovh-ca"
}

resource "ovh_vps" "bao" {
  # NOTE: The provider imports an empty purchase plan, not null.
  plan = []

  lifecycle {
    prevent_destroy = true
  }
}

import {
  to = ovh_vps.bao
  id = "vps-5c07e980.vps.ovh.ca"
}
