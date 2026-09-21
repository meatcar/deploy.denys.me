terraform {
  required_version = ">= 1.11.0"

  required_providers {
    railway = {
      source  = "terraform-community-providers/railway"
      version = "= 0.6.2"
    }
  }
}
