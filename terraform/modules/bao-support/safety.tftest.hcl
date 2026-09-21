mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }
}

run "kms_is_protected_and_least_privilege" {
  command = plan

  assert {
    condition     = aws_kms_key.openbao.enable_key_rotation && aws_kms_key.openbao.deletion_window_in_days == 30
    error_message = "The OpenBao KMS key must rotate and have a 30-day deletion window."
  }

  assert {
    condition     = aws_kms_alias.openbao.name == "alias/openbao-vpn" && aws_iam_user.openbao.name == "openbao-vpn-runtime"
    error_message = "The OpenBao KMS alias and runtime IAM user names must remain stable."
  }

  assert {
    condition = (
      length(data.aws_iam_policy_document.openbao.statement) == 1 &&
      toset(data.aws_iam_policy_document.openbao.statement[0].actions) == toset(["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt"]) &&
      data.aws_iam_policy_document.openbao.statement[0].resources == toset([aws_kms_key.openbao.arn])
    )
    error_message = "The OpenBao runtime policy must grant only the required KMS actions on its key."
  }

  assert {
    condition = (
      length(data.aws_iam_policy_document.aws_auth.statement) == 1 &&
      data.aws_iam_policy_document.aws_auth.statement[0].actions == toset(["iam:GetRole"]) &&
      data.aws_iam_policy_document.aws_auth.statement[0].resources == toset([
        "arn:aws:iam::148676508643:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_8e45cdd61884f702"
      ])
    )
    error_message = "The AWS auth verifier must only resolve the exact SSO administrator role."
  }
}

run "backup_is_single_private_and_durable" {
  command = plan

  assert {
    condition     = aws_s3_bucket.backup.bucket == "openbao-vpn-backup-123456789012" && aws_iam_user.backup.name == "openbao-vpn-backup"
    error_message = "There must be one Bao backup bucket and one Bao backup IAM user with stable names."
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.backup.block_public_acls &&
      aws_s3_bucket_public_access_block.backup.block_public_policy &&
      aws_s3_bucket_public_access_block.backup.ignore_public_acls &&
      aws_s3_bucket_public_access_block.backup.restrict_public_buckets
    )
    error_message = "The Bao backup bucket must block all public access."
  }

  assert {
    condition     = aws_s3_bucket_versioning.backup.versioning_configuration[0].status == "Enabled"
    error_message = "The Bao backup bucket must retain version history."
  }

  assert {
    condition = alltrue([for rule in aws_s3_bucket_server_side_encryption_configuration.backup.rule :
      alltrue([for defaults in rule.apply_server_side_encryption_by_default : defaults.sse_algorithm == "AES256"])
    ])
    error_message = "The Bao backup bucket must use server-side encryption."
  }

  assert {
    condition = (
      length(data.aws_iam_policy_document.backup_transport.statement) == 1 &&
      alltrue([for statement in data.aws_iam_policy_document.backup_transport.statement :
        statement.effect == "Deny" &&
        toset(statement.actions) == toset(["s3:*"]) &&
        toset(statement.resources) == toset([aws_s3_bucket.backup.arn, "${aws_s3_bucket.backup.arn}/*"]) &&
        alltrue([for condition in statement.condition :
          condition.test == "Bool" && condition.variable == "aws:SecureTransport" && toset(condition.values) == toset(["false"])
        ])
      ])
    )
    error_message = "The Bao backup bucket must deny all requests made without HTTPS."
  }
}

run "backup_user_is_least_privilege" {
  command = plan

  assert {
    condition = (
      length(data.aws_iam_policy_document.backup.statement) == 2 &&
      toset(data.aws_iam_policy_document.backup.statement[0].actions) == toset(["s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"]) &&
      data.aws_iam_policy_document.backup.statement[0].resources == toset([aws_s3_bucket.backup.arn]) &&
      toset(data.aws_iam_policy_document.backup.statement[1].actions) == toset(["s3:AbortMultipartUpload", "s3:DeleteObject", "s3:GetObject", "s3:ListMultipartUploadParts", "s3:PutObject"]) &&
      data.aws_iam_policy_document.backup.statement[1].resources == toset(["${aws_s3_bucket.backup.arn}/*"])
    )
    error_message = "The Restic IAM policy must grant only the required S3 actions on the Bao backup bucket."
  }

  assert {
    condition = (
      output.openbao_iam_user == "openbao-vpn-runtime" &&
      output.backup_bucket == "openbao-vpn-backup-123456789012" &&
      output.backup_iam_user == "openbao-vpn-backup"
    )
    error_message = "The Bao root must expose the required singular outputs."
  }
}
