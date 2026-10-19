locals {
  account_id = "148676508643"
  audience   = "urn:amp:aws:tofu-plan:148676508643"

  state_bucket_arn  = "arn:aws:s3:::terraform-state-denys-me"
  backup_bucket_arn = "arn:aws:s3:::${var.backup_bucket}"

  # NOTE: Refresh needs bucket metadata and key names, not backup contents.
  bucket_refresh_actions = [
    "s3:ListBucket",
    "s3:GetBucketPolicy",
    "s3:GetBucketAcl",
    "s3:GetBucketCORS",
    "s3:GetBucketWebsite",
    "s3:GetBucketVersioning",
    "s3:GetAccelerateConfiguration",
    "s3:GetBucketRequestPayment",
    "s3:GetBucketLogging",
    "s3:GetLifecycleConfiguration",
    "s3:GetReplicationConfiguration",
    "s3:GetEncryptionConfiguration",
    "s3:GetBucketObjectLockConfiguration",
    "s3:GetBucketTagging",
  ]
}

resource "aws_iam_openid_connect_provider" "amp" {
  url            = "https://ampcode.com/api/workload-identity"
  client_id_list = [local.audience]
}

resource "aws_iam_role" "plan" {
  name                 = "tofu-plan"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.amp.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "ampcode.com/api/workload-identity:aud" = local.audience
            "ampcode.com/api/workload-identity:sub" = "user:user_01K8F9XNBP340JTA7EXNMV9QW3:project:d652cd02-f7c9-4fd9-ad79-3eb9c935736e"
          }
        }
      },
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::148676508643:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_8e45cdd61884f702"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })
}

resource "aws_iam_role_policy" "refresh" {
  name = "main-root-refresh"
  role = aws_iam_role.plan.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "MainStateContent"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${local.state_bucket_arn}/state"]
      },
      {
        Sid      = "BucketConfiguration"
        Effect   = "Allow"
        Action   = local.bucket_refresh_actions
        Resource = [local.state_bucket_arn, local.backup_bucket_arn]
      },
      {
        Sid      = "BackupPublicAccessConfiguration"
        Effect   = "Allow"
        Action   = ["s3:GetBucketPublicAccessBlock"]
        Resource = [local.backup_bucket_arn]
      },
      {
        Sid    = "StateLockConfiguration"
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:DescribeContinuousBackups",
          "dynamodb:DescribeTimeToLive",
          "dynamodb:ListTagsOfResource",
        ]
        Resource = ["arn:aws:dynamodb:us-east-1:${local.account_id}:table/terraform-state-lock-denys-me"]
      },
      {
        Sid    = "UnsealKeyConfiguration"
        Effect = "Allow"
        Action = [
          "kms:DescribeKey",
          "kms:GetKeyPolicy",
          "kms:GetKeyRotationStatus",
          "kms:ListResourceTags",
        ]
        Resource = [var.openbao_kms_key_arn]
      },
      {
        Sid    = "UnsealAliasDiscovery"
        Effect = "Allow"
        Action = ["kms:ListAliases"]
        # NOTE: ListAliases does not support resource-level permissions.
        Resource = ["*"]
        Condition = {
          StringEquals = { "aws:RequestedRegion" = "ca-central-1" }
        }
      },
      {
        Sid      = "BaoUserConfiguration"
        Effect   = "Allow"
        Action   = ["iam:GetUser", "iam:GetUserPolicy"]
        Resource = ["arn:aws:iam::${local.account_id}:user/openbao-vpn-runtime", "arn:aws:iam::${local.account_id}:user/openbao-vpn-backup"]
      },
      {
        Sid      = "AmpIssuerConfiguration"
        Effect   = "Allow"
        Action   = ["iam:GetOpenIDConnectProvider"]
        Resource = [aws_iam_openid_connect_provider.amp.arn]
      },
      {
        Sid      = "PlanRoleConfiguration"
        Effect   = "Allow"
        Action   = ["iam:GetRole", "iam:ListRolePolicies", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies"]
        Resource = ["arn:aws:iam::${local.account_id}:role/tofu-plan"]
      },
      {
        Sid       = "DenyStateBucketMutations"
        Effect    = "Deny"
        NotAction = local.bucket_refresh_actions
        Resource  = [local.state_bucket_arn]
      },
      {
        Sid       = "DenyBackupBucketMutations"
        Effect    = "Deny"
        NotAction = concat(local.bucket_refresh_actions, ["s3:GetBucketPublicAccessBlock"])
        Resource  = [local.backup_bucket_arn]
      },
      {
        Sid      = "DenyBackupObjects"
        Effect   = "Deny"
        Action   = ["s3:*"]
        Resource = ["${local.backup_bucket_arn}/*"]
      },
      {
        Sid       = "DenyStateObjectMutations"
        Effect    = "Deny"
        NotAction = ["s3:GetObject"]
        Resource  = ["${local.state_bucket_arn}/*"]
      },
      {
        Sid         = "DenyOtherObjectReads"
        Effect      = "Deny"
        Action      = ["s3:GetObject*"]
        NotResource = ["${local.state_bucket_arn}/state"]
      },
    ]
  })
}
