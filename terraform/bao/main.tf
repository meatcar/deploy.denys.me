data "aws_caller_identity" "current" {}

resource "aws_kms_key" "openbao" {
  description             = "OpenBao auto-unseal for bao.vpn.denys.me"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "openbao" {
  name          = "alias/openbao-vpn"
  target_key_id = aws_kms_key.openbao.key_id
}

resource "aws_iam_user" "openbao" {
  name = "openbao-vpn-runtime"
}

data "aws_iam_policy_document" "openbao" {
  statement {
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
    ]
    resources = [aws_kms_key.openbao.arn]
  }
}

resource "aws_iam_user_policy" "openbao" {
  name   = "openbao-auto-unseal"
  user   = aws_iam_user.openbao.name
  policy = data.aws_iam_policy_document.openbao.json
}

resource "aws_s3_bucket" "backup" {
  bucket = "openbao-vpn-backup-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket = aws_s3_bucket.backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket     = aws_s3_bucket.backup.id
  depends_on = [aws_s3_bucket_versioning.backup]

  rule {
    id     = "bound-deleted-version-storage"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "backup_transport" {
  statement {
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.backup.arn, "${aws_s3_bucket.backup.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "backup" {
  bucket = aws_s3_bucket.backup.id
  policy = data.aws_iam_policy_document.backup_transport.json
}

resource "aws_iam_user" "backup" {
  name = "openbao-vpn-backup"
}

data "aws_iam_policy_document" "backup" {
  statement {
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
    ]
    resources = [aws_s3_bucket.backup.arn]
  }

  statement {
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:ListMultipartUploadParts",
      "s3:PutObject",
    ]
    resources = ["${aws_s3_bucket.backup.arn}/*"]
  }
}

resource "aws_iam_user_policy" "backup" {
  name   = "bao-restic-backup"
  user   = aws_iam_user.backup.name
  policy = data.aws_iam_policy_document.backup.json
}
