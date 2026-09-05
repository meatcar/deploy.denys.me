terraform {
  required_version = ">= 1.8.0"

  backend "s3" {
    bucket       = "terraform-state-denys-me"
    key          = "bao/state"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.50"
    }
  }
}

provider "aws" {
  region = "ca-central-1"
}
