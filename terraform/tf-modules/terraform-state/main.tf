# for state
provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "terraform-state-storage-s3" {
  bucket = "terraform-state-denys-me"

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "S3 Remote Terraform State Store for denys.me"
  }
}

resource "aws_s3_bucket_versioning" "terraform-state-storage-s3-versioning" {
  bucket = aws_s3_bucket.terraform-state-storage-s3.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_dynamodb_table" "dynamodb-terraform-state-lock" {
  name           = "terraform-state-lock-denys-me"
  hash_key       = "LockID"
  read_capacity  = 20
  write_capacity = 20

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "DynamoDB Terraform State Lock Table for denys.me"
  }
}
