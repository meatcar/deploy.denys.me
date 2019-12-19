terraform {
  backend "s3" {
    bucket         = "terraform-state-denys-me"
    key            = "state"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock-denys-me"
  }
}
